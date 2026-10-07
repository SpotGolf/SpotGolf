import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// Shared pins in memory, as CloudKit keeps them: one per hole per day.
final class FakePinSharing: PinSharing {
    var stored: [String: SharedPin] = [:]
    var hasAccount = true
    var failsUploads = false
    var failsFetches = false
    private(set) var fetchCount = 0
    private(set) var uploaded: [SharedPin] = []

    func isAccountAvailable() async -> Bool { hasAccount }

    func fetch(courseID: UUID, courseDate: String) async throws -> [SharedPin] {
        fetchCount += 1
        if failsFetches { throw URLError(.notConnectedToInternet) }
        return stored.values.filter { $0.courseID == courseID && $0.courseDate == courseDate }
    }

    func upload(_ pin: SharedPin) async throws {
        if failsUploads { throw URLError(.notConnectedToInternet) }
        uploaded.append(pin)
        stored[pin.recordName] = pin
    }
}

@MainActor
final class PinShareCoordinatorTests: XCTestCase {

    private var directory: URL!
    private var store: RoundStore!
    private var sharing: FakePinSharing!
    private var sharesPins = true
    private var coordinator: PinShareCoordinator!
    private var pinChanges = 0
    private let now = Date()

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = RoundStore(directory: directory)
        store.onPinsChanged = { [weak self] _ in self?.pinChanges += 1 }
        sharing = FakePinSharing()
        sharesPins = true
        pinChanges = 0
        coordinator = PinShareCoordinator(rounds: store, sharing: sharing,
                                          sharesPins: { [weak self] in self?.sharesPins ?? false },
                                          now: { [now] in now })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        coordinator = nil
        store = nil
        sharing = nil
        directory = nil
        super.tearDown()
    }

    private func onGreen(_ hole: Int, east: Double = 0) -> CLLocationCoordinate2D {
        let green = PathCourse.greens[hole]
        return PathCourse.coordinate(north: green.north, east: green.east + east).clLocation.coordinate
    }

    private func shared(_ hole: Int, east: Double = 0, setAt: Date? = nil, date: Date? = nil) -> SharedPin {
        let coordinate = onGreen(hole, east: east)
        return SharedPin(courseID: PathCourse.selection.course.id, subCourse: "Front", holeNumber: hole + 1,
                         courseDate: SharedPin.courseDate(for: date ?? now),
                         latitude: coordinate.latitude, longitude: coordinate.longitude, setAt: setAt ?? now)
    }

    private func store(_ pin: SharedPin) {
        sharing.stored[pin.recordName] = pin
    }

    /// Starts a round with its center pins, as `PhoneSync` does once the watch confirms it.
    private func startRound() async -> UUID {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        store.addCenterPins(roundID: id)
        await run()
        return id
    }

    private func run() async {
        await coordinator.check()
    }

    // MARK: - Start

    func testSharedPinsReplaceCenterPinsAtRoundStart() async {
        store(shared(1, east: 5))

        let id = await startRound()

        let round = store.round(id)
        XCTAssertEqual(round?.pins.count, 3)
        XCTAssertEqual(round?.pin(onHole: 0)?.source, .center)
        XCTAssertEqual(round?.pin(onHole: 1)?.source, .shared)
        XCTAssertEqual(round?.pin(onHole: 1)?.longitude ?? 0, onGreen(1, east: 5).longitude, accuracy: 1e-9)
        XCTAssertEqual(round?.pin(onHole: 2)?.source, .center)
        // Reported, so the watch gets them
        XCTAssertGreaterThan(pinChanges, 0)
    }

    func testFailedFetchStillGivesCenterPins() async {
        sharing.failsFetches = true

        let id = await startRound()

        XCTAssertEqual(store.round(id)?.pins.map(\.source), [.center, .center, .center])
    }

    func testSharedPinsOffTheGreenOrFromAnotherDayAreLeftOut() async {
        store(shared(0, east: 40))
        store(shared(1, date: now.addingTimeInterval(-24 * 60 * 60)))

        let id = await startRound()

        XCTAssertEqual(store.round(id)?.pins.map(\.source), [.center, .center, .center])
    }

    func testRoundsNotActiveAreLeftAlone() async {
        let id = store.startRound(courseSelection: PathCourse.selection, status: .starting).id

        await run()

        XCTAssertTrue(store.round(id)?.pins.isEmpty == true)
        XCTAssertEqual(sharing.fetchCount, 0)
    }

    // MARK: - End of a hole

    func testFetchesAgainWhenTheDisplayMovesToTheNextHole() async {
        let id = await startRound()
        store(shared(2))

        store.setDisplayHole(1, roundID: id)
        await run()

        XCTAssertEqual(sharing.fetchCount, 2)
        XCTAssertEqual(store.round(id)?.pin(onHole: 2)?.source, .shared)
    }

    func testGoingBackAndForwardDoesNotFetchAgain() async {
        let id = await startRound()
        store.setDisplayHole(2, roundID: id)
        await run()

        store.setDisplayHole(0, roundID: id)
        await run()
        store.setDisplayHole(1, roundID: id)
        await run()

        XCTAssertEqual(sharing.fetchCount, 2)
    }

    func testResumedRoundFetchesAgain() async {
        let id = await startRound()
        store.update(id) { $0.status = .ended }
        await run()

        store.update(id) { $0.status = .active }
        await run()

        XCTAssertEqual(sharing.fetchCount, 2)
    }

    // MARK: - Upload

    func testSetPinIsUploadedOnce() async {
        let id = await startRound()

        store.setPin(onGreen(1, east: 3), holeIndex: 1, roundID: id, at: now)
        await run()
        await run()

        XCTAssertEqual(sharing.uploaded.count, 1)
        XCTAssertEqual(sharing.uploaded.first?.holeNumber, 2)
        XCTAssertEqual(sharing.uploaded.first?.subCourse, "Front")
        XCTAssertEqual(sharing.uploaded.first?.courseID, PathCourse.selection.course.id)
    }

    func testCenterAndSharedPinsAreNotUploaded() async {
        store(shared(1))

        _ = await startRound()

        XCTAssertTrue(sharing.uploaded.isEmpty)
    }

    func testRoundWithSharingSwitchedOffSharesNothing() async {
        sharesPins = false
        store(shared(1))
        let id = await startRound()

        store.setPin(onGreen(0), holeIndex: 0, roundID: id, at: now)
        store.setDisplayHole(1, roundID: id)
        await run()

        XCTAssertEqual(sharing.fetchCount, 0)
        XCTAssertTrue(sharing.uploaded.isEmpty)
        XCTAssertEqual(store.round(id)?.pin(onHole: 1)?.source, .center)
    }

    func testRoundWithoutAnICloudAccountSharesNothing() async {
        sharing.hasAccount = false
        store(shared(1))
        let id = await startRound()

        store.setPin(onGreen(0), holeIndex: 0, roundID: id, at: now)
        store.setDisplayHole(1, roundID: id)
        await run()

        XCTAssertEqual(sharing.fetchCount, 0)
        XCTAssertTrue(sharing.uploaded.isEmpty)
        XCTAssertEqual(store.round(id)?.pin(onHole: 1)?.source, .center)
    }

    func testSharingIsDecidedOnlyWhenTheRoundStarts() async {
        sharesPins = false
        let id = await startRound()

        // Switched on mid-round, and then off mid-round in a round that started with it on
        sharesPins = true
        store.setPin(onGreen(0), holeIndex: 0, roundID: id, at: now.addingTimeInterval(-60))
        await run()
        XCTAssertTrue(sharing.uploaded.isEmpty)

        store.update(id) { $0.status = .ended }
        await run()
        store.update(id) { $0.status = .active }
        await run()
        sharesPins = false
        store.setPin(onGreen(1), holeIndex: 1, roundID: id, at: now.addingTimeInterval(60))
        await run()

        // The pin set while the round did not share stays unshared
        XCTAssertEqual(sharing.uploaded.map(\.holeNumber), [2])
    }

    func testPinSetByThePlayerIsKeptOverALaterSharedPin() async {
        let id = await startRound()
        store.setPin(onGreen(1), holeIndex: 1, roundID: id, at: now)
        await run()
        store(shared(1, east: 5, setAt: now.addingTimeInterval(60)))

        store.setDisplayHole(1, roundID: id)
        await run()

        XCTAssertEqual(store.round(id)?.pin(onHole: 1)?.source, .set)
        XCTAssertEqual(store.round(id)?.pin(onHole: 1)?.longitude, onGreen(1).longitude)
    }

    func testFailedUploadIsNotTriedAgain() async {
        let id = await startRound()
        sharing.failsUploads = true
        store.setPin(onGreen(1), holeIndex: 1, roundID: id, at: now)
        await run()

        sharing.failsUploads = false
        store.setDisplayHole(1, roundID: id)
        await run()

        XCTAssertTrue(sharing.uploaded.isEmpty)
        XCTAssertEqual(store.round(id)?.pin(onHole: 1)?.source, .set)
    }

    // MARK: - Shared pin

    func testRoundPinBecomesASharedPinByNineAndHoleNumber() {
        let round = Round(courseSelection: PathCourse.selection)
        let pin = PinLocation(holeIndex: 2, coordinate: onGreen(2), setAt: now)

        let sharedPin = round.sharedPin(for: pin)

        XCTAssertEqual(sharedPin, shared(2))
        XCTAssertNil(round.sharedPin(for: PinLocation(holeIndex: 9, coordinate: onGreen(2), setAt: now)))
    }

    func testSharedPinsBecomeRoundPinsOnlyForHolesPlayedAndOnTheGreen() {
        let round = Round(courseSelection: PathCourse.selection)
        let offCourse = SharedPin(courseID: PathCourse.selection.course.id, subCourse: "Back", holeNumber: 1,
                                  courseDate: "2026-10-06", latitude: 0, longitude: 0, setAt: now)

        let pins = round.pins(from: [shared(1), shared(0, east: 40), offCourse])

        XCTAssertEqual(pins, [PinLocation(holeIndex: 1, coordinate: onGreen(1), setAt: now, source: .shared)])
    }

    func testRecordNameIsOnePerHolePerDay() {
        let pin = shared(0)

        XCTAssertEqual(pin.recordName, "\(pin.courseID.uuidString)-Front-1-\(pin.courseDate)")
        XCTAssertEqual(SharedPin(courseID: pin.courseID, subCourse: "North Nine", holeNumber: 1, courseDate: "2026-10-06",
                                 latitude: 0, longitude: 0, setAt: now).recordName,
                       "\(pin.courseID.uuidString)-North%20Nine-1-2026-10-06")
    }

    func testCourseDateUsesTheTimeZone() {
        let date = Date(timeIntervalSince1970: 1_791_000_000) // 2026-10-03 04:00 UTC

        XCTAssertEqual(SharedPin.courseDate(for: date, timeZone: TimeZone(identifier: "UTC")!), "2026-10-03")
        XCTAssertEqual(SharedPin.courseDate(for: date, timeZone: TimeZone(identifier: "America/Denver")!), "2026-10-02")
    }
}
