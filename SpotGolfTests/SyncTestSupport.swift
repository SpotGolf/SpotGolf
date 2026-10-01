import Foundation
import CoreLocation
@testable import SpotGolf

struct FakeTransportError: Error {}

/// Connects two `SyncService`s in memory. Messages are delivered at once unless the test
/// holds them, drops them, or makes the other side unreachable.
@MainActor
final class FakeTransport: SyncTransport {
    weak var delegate: SyncTransportDelegate?
    weak var peer: FakeTransport?

    var isReachable = true {
        didSet { delegate?.transportReachabilityChanged() }
    }
    var hasCounterpart = true

    /// Sends fail before reaching the other side.
    var dropsSends = false
    /// Sends reach the other side, but the reply is lost.
    var dropsReplies = false
    /// Sends wait in `held` until `releaseHeld()`.
    var holdsSends = false

    /// Every message sent with `send`, in order.
    private(set) var sent: [SyncMessage] = []
    private(set) var queued: [[String: Any]] = []
    private(set) var context: [String: Any]?
    private var held: [() -> Void] = []

    var heldCount: Int { held.count }

    func send(_ payload: [String: Any],
              reply: @escaping ([String: Any]) -> Void,
              failure: @escaping (Error) -> Void) {
        if let message = SyncCodec.message(in: payload) {
            sent.append(message)
        }
        guard isReachable, let peer, peer.delegate != nil else {
            failure(SyncTransportError.unreachable)
            return
        }
        guard !dropsSends else {
            failure(FakeTransportError())
            return
        }
        let deliver = { [weak self] in
            let response = peer.delegate?.transport(didReceive: payload) ?? [:]
            if self?.dropsReplies == true {
                failure(FakeTransportError())
            } else {
                reply(response)
            }
        }
        if holdsSends {
            held.append(deliver)
        } else {
            deliver()
        }
    }

    func queue(_ payload: [String: Any]) {
        queued.append(payload)
    }

    func updateContext(_ payload: [String: Any]) {
        context = payload
    }

    /// Delivers held sends, in order or reversed.
    func releaseHeld(reversed: Bool = false) {
        let deliveries = reversed ? held.reversed() : held
        held = []
        deliveries.forEach { $0() }
    }

    /// Loses one held send: it never arrives and never fails.
    func discardHeld(at index: Int) {
        held.remove(at: index)
    }

    /// Delivers everything queued with `transferUserInfo`.
    func deliverQueued() {
        let payloads = queued
        queued = []
        for payload in payloads {
            peer?.delegate?.transport(didReceiveQueued: payload)
        }
    }

    /// Delivers the latest application context.
    func deliverContext() {
        guard let context else { return }
        peer?.delegate?.transport(didReceiveQueued: context)
    }

    func sentMessages<T>(_ extract: (SyncMessage) -> T?) -> [T] {
        sent.compactMap(extract)
    }
}

/// A phone and a watch linked by fake transports, each with its own files.
@MainActor
final class SyncPair {
    let directory: URL

    let phoneTransport = FakeTransport()
    let phoneSync: SyncService
    let phoneRounds: RoundStore
    let phoneStreams: StreamStore
    let phoneSuggestions: SuggestionStore
    let phone: PhoneSync

    let watchTransport = FakeTransport()
    let watchSync: SyncService
    let watchRounds: RoundStore
    let watchStreams: StreamStore
    let watch: WatchSync

    private(set) var watchAppLaunches = 0

    init(startTimeout: TimeInterval = PhoneSync.defaultStartTimeout,
         retryDelay: TimeInterval = PhoneSync.defaultRetryDelay) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let phoneDirectory = directory.appendingPathComponent("phone")
        let watchDirectory = directory.appendingPathComponent("watch")
        try! FileManager.default.createDirectory(at: phoneDirectory, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: watchDirectory, withIntermediateDirectories: true)

        phoneTransport.peer = watchTransport
        watchTransport.peer = phoneTransport

        phoneSync = SyncService(transport: phoneTransport)
        phoneRounds = RoundStore(directory: phoneDirectory)
        phoneStreams = StreamStore(directory: phoneDirectory.appendingPathComponent("streams"))
        phoneSuggestions = SuggestionStore(directory: phoneDirectory)
        var launches: (() -> Void)?
        // Hole starts are worked out on every batch, so tests don't wait for the throttle
        phone = PhoneSync(sync: phoneSync, rounds: phoneRounds, streams: phoneStreams, suggestions: phoneSuggestions,
                          startTimeout: startTimeout, retryDelay: retryDelay, timelineFixInterval: 0,
                          launchWatchApp: { launches?() })

        watchSync = SyncService(transport: watchTransport)
        watchRounds = RoundStore(directory: watchDirectory)
        watchStreams = StreamStore(directory: watchDirectory.appendingPathComponent("streams"))
        watch = WatchSync(sync: watchSync, rounds: watchRounds, streams: watchStreams)

        launches = { [weak self] in self?.watchAppLaunches += 1 }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Both devices reachable or not.
    func setReachable(_ reachable: Bool) {
        phoneTransport.isReachable = reachable
        watchTransport.isReachable = reachable
    }

    /// Starts a round on the phone and returns its ID.
    @discardableResult
    func startRound(_ selection: CourseSelection = .test) -> UUID {
        phone.startRound(courseSelection: selection)
    }
}

/// Test fixes and swings.
enum StreamFixtures {
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    static func location(_ second: TimeInterval, latitude: Double = 39.95545, longitude: Double = -105.0422) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                   altitude: 1620, horizontalAccuracy: 5, verticalAccuracy: 3,
                   timestamp: start.addingTimeInterval(second))
    }

    static func fix(_ second: TimeInterval, latitude: Double = 39.95545, longitude: Double = -105.0422) -> StreamRecord {
        .fix(TrackPoint(location: location(second, latitude: latitude, longitude: longitude)))
    }

    static func swing(_ second: TimeInterval, peakG: Float = 12.5) -> StreamRecord {
        .swing(StrokeSuggestion.swing(at: start.addingTimeInterval(second), peakG: peakG))
    }

    /// Fixes one second apart.
    static func fixes(_ seconds: Range<Int>) -> [StreamRecord] {
        seconds.map { fix(TimeInterval($0)) }
    }
}
