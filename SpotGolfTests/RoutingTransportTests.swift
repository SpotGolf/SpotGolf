import XCTest
@testable import SpotGolf

/// Answers every request with an empty reply.
@MainActor
private final class Receiver: SyncTransportDelegate {
    var received: [[String: Any]] = []
    var reachabilityChanges = 0

    func transport(didReceive payload: [String: Any]) -> [String: Any] {
        received.append(payload)
        return ["ok": true]
    }
    func transport(didReceiveQueued payload: [String: Any]) {}
    func transportReachabilityChanged() { reachabilityChanges += 1 }
    func transport(didReceiveFile url: URL, metadata: [String: Any]) {}
    func transport(didFinishFileTransfer metadata: [String: Any], error: Error?) {}
}

@MainActor
final class RoutingTransportTests: XCTestCase {

    private var watchFallback: FakeTransport!
    private var phoneFallback: FakeTransport!
    private var watchMirror: MirrorTransport!
    private var phoneMirror: MirrorTransport!
    private var watch: RoutingTransport!
    private var phone: RoutingTransport!
    private var watchReceiver: Receiver!
    private var phoneReceiver: Receiver!
    private var watchChannel: FakeMirrorChannel!
    private var phoneChannel: FakeMirrorChannel!

    override func setUp() async throws {
        try await super.setUp()
        watchFallback = FakeTransport()
        phoneFallback = FakeTransport()
        watchFallback.peer = phoneFallback
        phoneFallback.peer = watchFallback
        watchMirror = MirrorTransport(sendTimeout: 0.1)
        phoneMirror = MirrorTransport(sendTimeout: 0.1)
        watch = RoutingTransport(mirror: watchMirror, fallback: watchFallback)
        phone = RoutingTransport(mirror: phoneMirror, fallback: phoneFallback)
        watchReceiver = Receiver()
        phoneReceiver = Receiver()
        watch.delegate = watchReceiver
        phone.delegate = phoneReceiver
        (watchChannel, phoneChannel) = FakeMirrorChannel.pair()
    }

    private func connectMirroring() {
        watchMirror.attach(watchChannel)
        phoneMirror.attach(phoneChannel)
    }

    private func send(_ payload: [String: Any]) -> Result<[String: Any], Error>? {
        var result: Result<[String: Any], Error>?
        watch.send(payload, reply: { result = .success($0) }, failure: { result = .failure($0) })
        return result
    }

    func testSendsOverMirroringWhenConnected() throws {
        connectMirroring()

        let reply = try XCTUnwrap(send(["a": 1])).get()

        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertEqual(phoneReceiver.received.count, 1)
        XCTAssertTrue(watchFallback.sent.isEmpty)
    }

    func testSendsOverWatchConnectivityWhenMirroringIsNotConnected() throws {
        // As on simulators: attached, but nothing gets through
        watchChannel.isLinked = false
        watchMirror.attach(watchChannel)
        let mirrorSends = watchChannel.sendCount

        let reply = try XCTUnwrap(send(SyncCodec.payload(.sendLog))).get()

        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertEqual(watchFallback.sent, [.sendLog])
        XCTAssertEqual(watchChannel.sendCount, mirrorSends)
    }

    func testDisconnectedMirrorSendFallsBackOnce() throws {
        connectMirroring()
        watchChannel.isLinked = false

        let reply = try XCTUnwrap(send(SyncCodec.payload(.sendLog))).get()

        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertEqual(watchFallback.sent, [.sendLog])
        XCTAssertFalse(watchMirror.isConnected)
    }

    func testFallbackFailureIsReported() throws {
        connectMirroring()
        watchChannel.isLinked = false
        watchFallback.isReachable = false

        let result = try XCTUnwrap(send(["a": 1]))

        guard case .failure(SyncTransportError.unreachable) = result else { return XCTFail("expected unreachable") }
    }

    func testTimeoutDoesNotFallBack() {
        connectMirroring()
        watchChannel.swallowsSends = true
        let failed = expectation(description: "failed")

        watch.send(["a": 1], reply: { _ in XCTFail("no reply expected") }, failure: { error in
            if case SyncTransportError.timedOut = error { failed.fulfill() }
        })
        wait(for: [failed], timeout: 2)

        XCTAssertTrue(watchFallback.sent.isEmpty)
    }

    func testReachableWhenEitherChannelIs() {
        watchFallback.isReachable = false
        XCTAssertFalse(watch.isReachable)

        connectMirroring()
        XCTAssertTrue(watch.isReachable)

        watchMirror.detach()
        watchFallback.isReachable = true
        XCTAssertTrue(watch.isReachable)
    }

    func testMirroringChangesReachDelegate() {
        let before = watchReceiver.reachabilityChanges

        connectMirroring()

        XCTAssertEqual(watchReceiver.reachabilityChanges, before + 1)
    }

    func testQueueContextAndFilesAlwaysUseWatchConnectivity() throws {
        connectMirroring()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        watch.queue(["q": 1])
        watch.updateContext(["c": 2])
        watch.transferFile(url, metadata: ["f": 3])

        XCTAssertEqual(watchFallback.queued.count, 1)
        XCTAssertEqual(watchFallback.context?["c"] as? Int, 2)
        XCTAssertEqual(watch.outstandingFileTransfers.first?["f"] as? Int, 3)
    }
}
