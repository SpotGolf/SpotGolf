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
            "mark": markData
        ]

        service.handleMessage(message)

        XCTAssertEqual(store.rounds[0].marks.count, 1)
        XCTAssertEqual(store.rounds[0].marks[0].id, mark.id)
        XCTAssertEqual(store.rounds[0].marks[0].latitude, 33.45)
    }

    func testHandleAddMarkWithInvalidRoundIDIsIgnored() {
        store.startRound(fromSync: true)

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markData = try! JSONEncoder().encode(mark)

        let message: [String: Any] = [
            "type": "addMark",
            "roundId": "not-a-uuid",
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
            "mark": Data([0x00, 0x01, 0x02])
        ]

        service.handleMessage(message)

        XCTAssertTrue(store.rounds[0].marks.isEmpty)
    }

    func testHandleAddMarkWithMissingMarkDataIsIgnored() {
        let roundID = UUID()
        store.startRound(id: roundID, fromSync: true)

        let message: [String: Any] = [
            "type": "addMark",
            "roundId": roundID.uuidString
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
