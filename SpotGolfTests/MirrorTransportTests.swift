import XCTest
@testable import SpotGolf

/// Answers each request with `reply`, and counts connection changes.
@MainActor
private final class MirrorDelegate: MirrorTransportDelegate {
    var received: [[String: Any]] = []
    var reply: [String: Any] = [:]
    var connectionChanges = 0

    func mirror(didReceive payload: [String: Any]) -> [String: Any] {
        received.append(payload)
        return reply
    }

    func mirrorConnectionChanged() {
        connectionChanges += 1
    }
}

@MainActor
final class MirrorTransportTests: XCTestCase {

    private var watch: MirrorTransport!
    private var phone: MirrorTransport!
    private var watchDelegate: MirrorDelegate!
    private var phoneDelegate: MirrorDelegate!
    private var watchChannel: FakeMirrorChannel!
    private var phoneChannel: FakeMirrorChannel!

    override func setUp() async throws {
        try await super.setUp()
        watch = MirrorTransport(sendTimeout: 0.1, maxWaiting: 2)
        phone = MirrorTransport(sendTimeout: 0.1, maxWaiting: 2)
        watchDelegate = MirrorDelegate()
        phoneDelegate = MirrorDelegate()
        watch.delegate = watchDelegate
        phone.delegate = phoneDelegate
        (watchChannel, phoneChannel) = FakeMirrorChannel.pair()
    }

    private func connect() {
        watch.attach(watchChannel)
        phone.attach(phoneChannel)
    }

    // MARK: - Connecting

    func testHellosConnectBothSides() {
        connect()

        XCTAssertTrue(watch.isConnected)
        XCTAssertTrue(phone.isConnected)
        XCTAssertEqual(watchDelegate.connectionChanges, 1)
        XCTAssertEqual(phoneDelegate.connectionChanges, 1)
        // Hellos never reach the delegate
        XCTAssertTrue(watchDelegate.received.isEmpty)
        XCTAssertTrue(phoneDelegate.received.isEmpty)
    }

    func testAttachedIsNotConnectedUntilSomethingArrives() {
        // As on simulators: mirroring starts, but nothing gets through
        watchChannel.isLinked = false
        watch.attach(watchChannel)

        XCTAssertFalse(watch.isConnected)
        XCTAssertEqual(watchDelegate.connectionChanges, 0)

        var failure: Error?
        watch.send(["a": 1], reply: { _ in XCTFail("no reply expected") }, failure: { failure = $0 })
        guard case SyncTransportError.unreachable = failure! else { return XCTFail("expected unreachable") }
    }

    func testLaterHelloConnectsOnceTheLinkWorks() {
        watchChannel.isLinked = false
        phoneChannel.isLinked = false
        connect()
        XCTAssertFalse(watch.isConnected)

        watchChannel.isLinked = true
        phoneChannel.isLinked = true
        watch.sayHello()

        XCTAssertTrue(watch.isConnected)
        XCTAssertTrue(phone.isConnected)
    }

    // MARK: - Sending

    func testRequestGetsTheReply() {
        connect()
        phoneDelegate.reply = ["answer": 42]

        var reply: [String: Any]?
        watch.send(["question": "what"], reply: { reply = $0 }, failure: { XCTFail("\($0)") })

        XCTAssertEqual(phoneDelegate.received.first?["question"] as? String, "what")
        XCTAssertEqual(reply?["answer"] as? Int, 42)
    }

    func testEmptyReplyStillRunsReply() {
        connect()

        var replied = false
        phone.send(["a": 1], reply: { replied = $0.isEmpty }, failure: { XCTFail("\($0)") })

        XCTAssertTrue(replied)
        XCTAssertEqual(watchDelegate.received.count, 1)
    }

    func testDataValuesSurviveTheEnvelope() {
        connect()
        let data = Data((0..<255).map { UInt8($0) })

        watch.send(["data": data], reply: { _ in }, failure: { XCTFail("\($0)") })

        XCTAssertEqual(phoneDelegate.received.first?["data"] as? Data, data)
    }

    func testUnansweredSendTimesOutAndTheNextGoes() {
        connect()
        watchChannel.swallowsSends = true
        let timedOut = expectation(description: "timed out")
        watch.send(["a": 1], reply: { _ in XCTFail("no reply expected") }, failure: { error in
            if case SyncTransportError.timedOut = error { timedOut.fulfill() }
        })
        var replied = false
        watch.send(["b": 2], reply: { _ in replied = true }, failure: { XCTFail("\($0)") })
        XCTAssertFalse(replied, "the second send waits for the first")

        watchChannel.swallowsSends = false
        wait(for: [timedOut], timeout: 2)

        XCTAssertTrue(replied)
        // A timeout leaves the link up, since the other side may have the message
        XCTAssertTrue(watch.isConnected)
    }

    func testOneSendInFlightAndTooManyWaitingFailsTheOldest() {
        connect()
        watchChannel.swallowsSends = true
        let sendsBefore = watchChannel.sendCount
        var failures: [Int] = []
        for index in 0..<4 {
            watch.send(["i": index], reply: { _ in }, failure: { error in
                if case SyncTransportError.tooManyWaiting = error { failures.append(index) }
            })
        }

        // 0 is in flight, 1 to 3 wait, and only 2 may
        XCTAssertEqual(failures, [1])
        XCTAssertEqual(watchChannel.sendCount - sendsBefore, 1)
    }

    func testFailedSendDisconnectsAndFailsWaitingSends() {
        connect()
        watchChannel.isLinked = false
        var errors: [Error] = []
        watch.send(["a": 1], reply: { _ in XCTFail("no reply expected") }, failure: { errors.append($0) })

        XCTAssertFalse(watch.isConnected)
        XCTAssertEqual(watchDelegate.connectionChanges, 2)
        XCTAssertEqual(errors.count, 1)
        guard case SyncTransportError.unreachable = errors[0] else { return XCTFail("expected unreachable") }
    }

    func testDisconnectFailsSendInFlight() {
        connect()
        watchChannel.swallowsSends = true
        var errors: [Error] = []
        watch.send(["a": 1], reply: { _ in }, failure: { errors.append($0) })
        watch.send(["b": 2], reply: { _ in }, failure: { errors.append($0) })

        watchChannel.onDisconnect?()

        XCTAssertFalse(watch.isConnected)
        XCTAssertEqual(errors.count, 2)
    }

    func testDetachDisconnects() {
        connect()

        watch.detach()

        XCTAssertFalse(watch.isConnected)
        XCTAssertNil(watch.channel)
        XCTAssertEqual(watchDelegate.connectionChanges, 2)
    }

    func testEndedChannelIsDetached() {
        connect()
        let sendsBefore = phoneChannel.sendCount

        phoneChannel.onEnd?()

        XCTAssertNil(phone.channel)
        XCTAssertFalse(phone.isConnected)
        // No more hellos on the ended session
        phone.sayHello()
        XCTAssertEqual(phoneChannel.sendCount, sendsBefore)
    }

    func testOldChannelEndingLeavesTheNewOne() {
        connect()
        let (newWatch, newPhone) = FakeMirrorChannel.pair()
        watch.attach(newWatch)
        phone.attach(newPhone)

        phoneChannel.onEnd?()

        XCTAssertTrue(phone.channel === newPhone)
        XCTAssertTrue(phone.isConnected)
    }

    func testNewChannelReplacesTheOld() {
        connect()
        let (newWatch, newPhone) = FakeMirrorChannel.pair()

        watch.attach(newWatch)
        phone.attach(newPhone)

        XCTAssertTrue(watch.isConnected)
        XCTAssertTrue(phone.isConnected)
        // The old channel's data is ignored
        watchChannel.onDisconnect?()
        XCTAssertTrue(watch.isConnected)
    }

    // MARK: - Envelope

    func testEnvelopeRoundTrips() throws {
        let envelope = MirrorEnvelope(id: UUID(), inReplyTo: UUID(),
                                      payload: try MirrorEnvelope.payloadData(["k": "v"]))

        let decoded = try MirrorEnvelope.decoded(from: envelope.encoded())

        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(MirrorEnvelope.payload(from: decoded.payload)["k"] as? String, "v")
    }

    func testEmptyPayloadIsEmptyData() throws {
        XCTAssertTrue(try MirrorEnvelope.payloadData([:]).isEmpty)
        XCTAssertTrue(MirrorEnvelope.payload(from: Data()).isEmpty)
    }
}
