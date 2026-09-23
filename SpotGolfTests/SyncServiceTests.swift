import XCTest
import CoreLocation
import CourseDataSwift
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

    /// Delivers a startRound message the way the phone sends it: a header, then the course in one chunk.
    private func handleStartRound(id: String, date: String?, selection: CourseSelection = .test) {
        let compressed = try! JSONEncoder().encode(selection).gzipCompressed()
        let transferID = UUID().uuidString
        var header: [String: Any] = [
            "type": "startRound",
            "id": id,
            "_chunked": true,
            "_transferId": transferID,
            "_totalChunks": 1,
            "_totalBytes": compressed.count
        ]
        header["date"] = date
        service.handleMessage(header)
        service.handleMessage([
            "_chunk": true,
            "_transferId": transferID,
            "_chunkIndex": 0,
            "_data": compressed
        ])
    }

    func testHandleStartRoundMessage() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        handleStartRound(id: id.uuidString, date: ISO8601DateFormatter().string(from: date))

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertEqual(store.rounds[0].id, id)
        XCTAssertTrue(store.rounds[0].isActive)
    }

    func testHandleStartRoundMessageSetsCorrectDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()

        handleStartRound(id: UUID().uuidString, date: formatter.string(from: date))

        let roundDate = store.rounds[0].date
        XCTAssertEqual(formatter.string(from: roundDate), formatter.string(from: date))
    }

    func testHandleStartRoundMessageSetsCourse() {
        let selection = CourseSelection(course: CourseSelection.test.course, selectedSubCourseIndices: [1])

        handleStartRound(id: UUID().uuidString, date: ISO8601DateFormatter().string(from: Date()), selection: selection)

        XCTAssertEqual(store.rounds[0].course.name, "Test Course")
        XCTAssertEqual(store.rounds[0].courseSelection.selectedSubCourseIndices, [1])
    }

    func testHandleStartRoundWithInvalidIDIsIgnored() {
        handleStartRound(id: "not-a-uuid", date: ISO8601DateFormatter().string(from: Date()))

        XCTAssertTrue(store.rounds.isEmpty)
    }

    func testHandleStartRoundWithMissingDateIsIgnored() {
        handleStartRound(id: UUID().uuidString, date: nil)

        XCTAssertTrue(store.rounds.isEmpty)
    }

    // MARK: - endRound message

    func testHandleEndRoundMessage() {
        let id = UUID()
        store.startRound(id: id, courseSelection: .test, fromSync: true)
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
        store.startRound(courseSelection: .test, fromSync: true)

        let message: [String: Any] = [
            "type": "endRound",
            "id": "not-a-uuid"
        ]

        service.handleMessage(message)

        XCTAssertNotNil(store.activeRound)
    }

    func testHandleEndRoundWithMissingIDIsIgnored() {
        store.startRound(courseSelection: .test, fromSync: true)

        let message: [String: Any] = [
            "type": "endRound"
        ]

        service.handleMessage(message)

        XCTAssertNotNil(store.activeRound)
    }

    // MARK: - addMark message

    func testHandleAddMarkMessage() {
        let roundID = UUID()
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)

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
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)
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
        store.startRound(courseSelection: .test, fromSync: true)

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
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)

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
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)

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

    // MARK: - Course encoding

    func testSendAndHandleCourseSelection() throws {
        // Create a CourseSelection, encode it, verify it round-trips through the message format
        let selection = CourseSelection(
            course: Course(name: "Test", clubName: "Test",
                           location: CourseLocation(address: "", city: "Denver",
                                                    state: "CO", country: "US",
                                                    coordinate: Coordinate(latitude: 39.0, longitude: -105.0)),
                           subCourses: []),
            selectedSubCourseIndices: [0, 1]
        )

        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(CourseSelection.self, from: data)
        XCTAssertEqual(decoded.course.name, "Test")
        XCTAssertEqual(decoded.selectedSubCourseIndices, [0, 1])
    }

    // MARK: - setMarkType message

    func testHandleSetMarkTypeMessage() {
        let roundID = UUID()
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)
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
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)
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
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)
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
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)
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

        handleStartRound(id: UUID().uuidString, date: ISO8601DateFormatter().string(from: Date()))

        XCTAssertTrue(store.rounds.count == 1, "The round should be created")
        XCTAssertTrue(syncMessages.isEmpty, "Handled messages should use fromSync: true")
    }

    // MARK: - setHole message

    func testHandleSetHoleMessage() {
        let roundID = UUID()
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)

        service.handleMessage([
            "type": "setHole",
            "roundId": roundID.uuidString,
            "holeIndex": 6,
            "changedAt": Date().addingTimeInterval(1).timeIntervalSince1970
        ])

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 6)
    }

    func testHandleSetHoleDoesNotEchoBack() {
        let roundID = UUID()
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)
        var syncMessages: [SyncMessage] = []
        store.onSyncEvent = { syncMessages.append($0) }

        service.handleMessage([
            "type": "setHole",
            "roundId": roundID.uuidString,
            "holeIndex": 6,
            "changedAt": Date().addingTimeInterval(1).timeIntervalSince1970
        ])

        XCTAssertTrue(syncMessages.isEmpty, "A hole change from the other device should not be sent back")
    }

    func testHandleSetHoleWithMissingFieldsIsIgnored() {
        let roundID = UUID()
        store.startRound(id: roundID, courseSelection: .test, fromSync: true)

        service.handleMessage(["type": "setHole", "roundId": roundID.uuidString, "holeIndex": 6])
        service.handleMessage(["type": "setHole", "holeIndex": 6, "changedAt": Date().timeIntervalSince1970 + 1])

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 0)
    }

    // MARK: - Received track files

    func testHandleReceivedTrackImportsAndRemovesFile() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tracks = TrackStore(directory: directory)
        service.trackStore = tracks

        // Build the file the way the watch would send it
        let roundID = UUID()
        let sender = TrackStore(directory: directory.appendingPathComponent("sender"))
        sender.append([CLLocation(latitude: 39.95545, longitude: -105.0422)],
                      roundID: roundID, source: .watch)
        sender.flush()
        let received = sender.fileURL(for: roundID, source: .watch)

        service.handleReceivedTrack(at: received, roundID: roundID, source: .watch)

        XCTAssertEqual(tracks.points(for: roundID, source: .watch).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: received.path))
    }

    func testHandleTrackSegmentMessageImportsPoints() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tracks = TrackStore(directory: directory)
        service.trackStore = tracks

        // Build segment data the way the watch would send it
        let roundID = UUID()
        let sender = TrackStore(directory: directory.appendingPathComponent("sender"))
        sender.append([CLLocation(latitude: 39.95545, longitude: -105.0422)],
                      roundID: roundID, source: .watch)
        sender.flush()
        let data = try Data(contentsOf: sender.fileURL(for: roundID, source: .watch))

        service.handleMessage([
            "type": "trackSegment",
            "roundId": roundID.uuidString,
            "source": "watch",
            "data": data
        ])

        XCTAssertEqual(tracks.points(for: roundID, source: .watch).count, 1)
    }

    func testHandleTrackSegmentWithMissingFieldsIsIgnored() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tracks = TrackStore(directory: directory)
        service.trackStore = tracks
        let roundID = UUID()

        service.handleMessage(["type": "trackSegment", "roundId": roundID.uuidString, "source": "watch"])
        service.handleMessage(["type": "trackSegment", "roundId": roundID.uuidString, "data": Data()])

        XCTAssertTrue(tracks.points(for: roundID, source: .watch).isEmpty)
    }
}
