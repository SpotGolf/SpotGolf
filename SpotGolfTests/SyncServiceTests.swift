import XCTest
import CoreLocation
@testable import SpotGolf

@MainActor
final class SyncServiceTests: XCTestCase {

    private var service: SyncService!
    private var store: RoundStore!

    override func setUp() {
        super.setUp()
        service = SyncService()
        store = RoundStore()
        store.rounds = []
        service.roundStore = store
    }

    override func tearDown() {
        service = nil
        store = nil
        super.tearDown()
    }

    // MARK: - startRound message

    func testHandleStartRoundMessage() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let message: [String: Any] = [
            "type": "startRound",
            "id": id.uuidString,
            "date": ISO8601DateFormatter().string(from: date)
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertEqual(store.rounds[0].id, id)
        XCTAssertTrue(store.rounds[0].isActive)
    }

    func testHandleStartRoundMessageSetsCorrectDate() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        let message: [String: Any] = [
            "type": "startRound",
            "id": id.uuidString,
            "date": formatter.string(from: date)
        ]

        service.handleMessage(message)

        let roundDate = store.rounds[0].date
        XCTAssertEqual(formatter.string(from: roundDate), formatter.string(from: date))
    }

    func testHandleStartRoundWithInvalidIDIsIgnored() {
        let message: [String: Any] = [
            "type": "startRound",
            "id": "not-a-uuid",
            "date": ISO8601DateFormatter().string(from: Date())
        ]

        service.handleMessage(message)

        XCTAssertTrue(store.rounds.isEmpty)
    }

    func testHandleStartRoundWithMissingDateIsIgnored() {
        let message: [String: Any] = [
            "type": "startRound",
            "id": UUID().uuidString
        ]

        service.handleMessage(message)

        XCTAssertTrue(store.rounds.isEmpty)
    }

    // MARK: - endRound message

    func testHandleEndRoundMessage() {
        let id = UUID()
        store.startRound(id: id, fromSync: true)
        XCTAssertNotNil(store.activeRound)

        let message: [String: Any] = [
            "type": "endRound",
            "id": id.uuidString
        ]

        service.handleMessage(message)

        XCTAssertNil(store.activeRound)
        XCTAssertFalse(store.rounds[0].isActive)
    }

    func testHandleEndRoundWithInvalidIDIsIgnored() {
        store.startRound(fromSync: true)

        let message: [String: Any] = [
            "type": "endRound",
            "id": "not-a-uuid"
        ]

        service.handleMessage(message)

        XCTAssertNotNil(store.activeRound)
    }

    func testHandleEndRoundWithMissingIDIsIgnored() {
        store.startRound(fromSync: true)

        let message: [String: Any] = [
            "type": "endRound"
        ]

        service.handleMessage(message)

        XCTAssertNotNil(store.activeRound)
    }

    // MARK: - addMark message

    func testHandleAddMarkMessage() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markData = try! JSONEncoder().encode(mark)

        let message: [String: Any] = [
            "type": "addMark",
            "roundId": roundID.uuidString,
            "holeIndex": 0,
            "mark": markData
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds[0].marks.count, 1)
        XCTAssertEqual(store.rounds[0].marks[0].id, mark.id)
        XCTAssertEqual(store.rounds[0].marks[0].latitude, 33.45)
    }

    func testHandleAddMarkToSpecificHole() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)
        store.nextHole() // iOS is on hole 1

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markData = try! JSONEncoder().encode(mark)

        // Watch sends mark for hole 0
        let message: [String: Any] = [
            "type": "addMark",
            "roundId": roundID.uuidString,
            "holeIndex": 0,
            "mark": markData
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds[0].holes[0].marks.count, 1, "Mark should go to hole 0")
        XCTAssertTrue(store.rounds[0].holes[1].marks.isEmpty, "Hole 1 should have no marks")
    }

    func testHandleAddMarkWithInvalidRoundIDIsIgnored() {
        store.startRound(fromSync: true)

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markData = try! JSONEncoder().encode(mark)

        let message: [String: Any] = [
            "type": "addMark",
            "roundId": "not-a-uuid",
            "holeIndex": 0,
            "mark": markData
        ]

        service.handleMessage(message)

        XCTAssertTrue(store.rounds[0].marks.isEmpty)
    }

    func testHandleAddMarkWithInvalidMarkDataIsIgnored() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)

        let message: [String: Any] = [
            "type": "addMark",
            "roundId": roundID.uuidString,
            "holeIndex": 0,
            "mark": Data([0x00, 0x01, 0x02])
        ]

        service.handleMessage(message)

        XCTAssertTrue(store.rounds[0].marks.isEmpty)
    }

    func testHandleAddMarkWithMissingHoleIndexIsIgnored() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markData = try! JSONEncoder().encode(mark)

        let message: [String: Any] = [
            "type": "addMark",
            "roundId": roundID.uuidString,
            "mark": markData
        ]

        service.handleMessage(message)

        XCTAssertTrue(store.rounds[0].marks.isEmpty)
    }

    // MARK: - Unknown and empty messages

    func testHandleUnknownTypeIsIgnored() {
        let message: [String: Any] = [
            "type": "deleteMark",
            "id": UUID().uuidString
        ]

        service.handleMessage(message)

        XCTAssertTrue(store.rounds.isEmpty)
    }

    func testHandleMissingTypeIsIgnored() {
        let message: [String: Any] = [
            "id": UUID().uuidString
        ]

        service.handleMessage(message)

        XCTAssertTrue(store.rounds.isEmpty)
    }

    func testHandleEmptyMessageIsIgnored() {
        service.handleMessage([:])

        XCTAssertTrue(store.rounds.isEmpty)
    }

    // MARK: - setCourse message

    func testSendAndHandleCourseSelection() throws {
        // Create a CourseSelection, encode it, verify it round-trips through the message format
        let selection = CourseSelection(
            course: Course(id: "C1", name: "Test", clubName: "Test",
                           location: CourseLocation(address: nil, city: "Denver",
                                                    coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                                                    country: "US", state: "CO"),
                           subCourses: []),
            selectedSubCourseIndices: [0, 1]
        )

        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(CourseSelection.self, from: data)
        XCTAssertEqual(decoded.course.id, "C1")
        XCTAssertEqual(decoded.selectedSubCourseIndices, [0, 1])
    }

    func testHandleSetCourseMessage() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)

        let selection = CourseSelection(
            course: Course(id: "C1", name: "Test", clubName: "Test",
                           location: CourseLocation(address: nil, city: "Denver",
                                                    coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                                                    country: "US", state: "CO"),
                           subCourses: []),
            selectedSubCourseIndices: [0, 1]
        )
        let data = try! JSONEncoder().encode(selection)

        let message: [String: Any] = [
            "type": "setCourse",
            "roundId": roundID.uuidString,
            "courseSelection": data
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds[0].courseSelection?.course.id, "C1")
        XCTAssertEqual(store.rounds[0].courseSelection?.selectedSubCourseIndices, [0, 1])
    }

    func testHandleSetCourseWithInvalidRoundIDIsIgnored() {
        store.startRound(fromSync: true)

        let selection = CourseSelection(
            course: Course(id: "C1", name: "Test", clubName: "Test",
                           location: CourseLocation(address: nil, city: "Denver",
                                                    coordinate: CourseCoordinate(latitude: 39.0, longitude: -105.0),
                                                    country: "US", state: "CO"),
                           subCourses: []),
            selectedSubCourseIndices: []
        )
        let data = try! JSONEncoder().encode(selection)

        let message: [String: Any] = [
            "type": "setCourse",
            "roundId": "not-a-uuid",
            "courseSelection": data
        ]

        service.handleMessage(message)

        XCTAssertNil(store.rounds[0].courseSelection)
    }

    // MARK: - setMarkType message

    func testHandleSetMarkTypeMessage() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, holeIndex: 0, mark: mark, fromSync: true)

        let message: [String: Any] = [
            "type": "setMarkType",
            "markId": mark.id.uuidString,
            "markType": "penalty",
            "roundId": roundID.uuidString
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds[0].marks[0].type, .penalty)
    }

    func testHandleSetMarkTypeOutOfBoundsMessage() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, holeIndex: 0, mark: mark, fromSync: true)

        let message: [String: Any] = [
            "type": "setMarkType",
            "markId": mark.id.uuidString,
            "markType": "outOfBounds",
            "roundId": roundID.uuidString
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds[0].marks[0].type, .outOfBounds)
    }

    func testHandleSetMarkTypeWithInvalidMarkIDIsIgnored() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, holeIndex: 0, mark: mark, fromSync: true)

        let message: [String: Any] = [
            "type": "setMarkType",
            "markId": UUID().uuidString,
            "markType": "penalty",
            "roundId": roundID.uuidString
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds[0].marks[0].type, .regular)
    }

    func testHandleSetMarkTypeWithInvalidTypeIsIgnored() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, holeIndex: 0, mark: mark, fromSync: true)

        let message: [String: Any] = [
            "type": "setMarkType",
            "markId": mark.id.uuidString,
            "markType": "invalidType",
            "roundId": roundID.uuidString
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds[0].marks[0].type, .regular)
    }

    // MARK: - Messages are applied via fromSync

    func testHandleMessagesDoNotTriggerSyncEvents() {
        var syncMessages: [SyncMessage] = []
        store.onSyncEvent = { syncMessages.append($0) }

        let id = UUID()
        service.handleMessage([
            "type": "startRound",
            "id": id.uuidString,
            "date": ISO8601DateFormatter().string(from: Date())
        ])

        XCTAssertTrue(syncMessages.isEmpty, "Handled messages should use fromSync: true")
    }
}
