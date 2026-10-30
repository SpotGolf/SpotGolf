import Foundation
import SwiftData
import CoreLocation
import CourseDataSwift
import XCTest
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

    /// Files sent with `transferFile`, waiting for `deliverFiles()`.
    private(set) var files: [(url: URL, metadata: [String: Any])] = []

    func transferFile(_ url: URL, metadata: [String: Any]) {
        files.append((url, metadata))
    }

    var outstandingFileTransfers: [[String: Any]] { files.map(\.metadata) }

    /// Delivers every file sent: the other side gets a copy, and this side hears it arrived.
    func deliverFiles() {
        let sending = files
        files = []
        for file in sending {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.copyItem(at: file.url, to: copy)
            peer?.delegate?.transport(didReceiveFile: copy, metadata: file.metadata)
            delegate?.transport(didFinishFileTransfer: file.metadata, error: nil)
        }
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

/// Links two `MirrorTransport`s in memory, as a mirrored workout session does. Data arrives
/// at once while linked. Unlinked, sends fail, as they do on simulators or out of range.
@MainActor
final class FakeMirrorChannel: MirrorChannel {
    weak var peer: FakeMirrorChannel?
    var onReceive: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onEnd: (() -> Void)?

    var isLinked = true
    /// Sends go nowhere and never finish, so a request waits for its timeout.
    var swallowsSends = false

    /// Every send, including hellos and replies.
    private(set) var sendCount = 0

    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        sendCount += 1
        guard !swallowsSends else { return }
        guard isLinked, let peer else {
            completion(FakeTransportError())
            return
        }
        peer.onReceive?(data)
        completion(nil)
    }

    /// Two channels linked to each other.
    static func pair() -> (FakeMirrorChannel, FakeMirrorChannel) {
        let a = FakeMirrorChannel()
        let b = FakeMirrorChannel()
        a.peer = b
        b.peer = a
        return (a, b)
    }
}

/// A phone and a watch linked by fake transports, each with its own saved data. Each side
/// sends through a `RoutingTransport`: over WatchConnectivity's fake until
/// `connectMirroring()`, then over a fake mirrored session.
@MainActor
final class SyncPair {
    let phoneContainer = Storage.inMemoryContainer()
    let watchContainer = Storage.inMemoryContainer()

    let phoneTransport = FakeTransport()
    let phoneMirror = MirrorTransport()
    let phoneSync: SyncService
    let phoneRounds: RoundStore
    let phoneStreams: StreamStore
    let phone: PhoneSync

    let watchTransport = FakeTransport()
    let watchMirror = MirrorTransport()
    private(set) var phoneChannel: FakeMirrorChannel?
    private(set) var watchChannel: FakeMirrorChannel?
    let watchSync: SyncService
    let watchRounds: RoundStore
    let watchStreams: StreamStore
    let watch: WatchSync

    private(set) var watchAppLaunches = 0

    init(startTimeout: TimeInterval = SyncService.startTimeout,
         retryDelay: TimeInterval = PhoneSync.defaultRetryDelay) {
        phoneTransport.peer = watchTransport
        watchTransport.peer = phoneTransport

        phoneSync = SyncService(transport: RoutingTransport(mirror: phoneMirror, fallback: phoneTransport))
        phoneRounds = RoundStore(context: phoneContainer.mainContext)
        phoneStreams = StreamStore(context: phoneContainer.mainContext)
        var launches: (() -> Void)?
        phone = PhoneSync(sync: phoneSync, rounds: phoneRounds, streams: phoneStreams,
                          startTimeout: startTimeout, retryDelay: retryDelay,
                          launchWatchApp: { launches?() })

        watchSync = SyncService(transport: RoutingTransport(mirror: watchMirror, fallback: watchTransport))
        watchRounds = RoundStore(context: watchContainer.mainContext)
        watchStreams = StreamStore(context: watchContainer.mainContext)
        watch = WatchSync(sync: watchSync, rounds: watchRounds, streams: watchStreams)

        launches = { [weak self] in self?.watchAppLaunches += 1 }
    }

    /// Nothing to clean up: each pair's data is in memory.
    func cleanUp() {}

    /// Both devices reachable or not.
    func setReachable(_ reachable: Bool) {
        phoneTransport.isReachable = reachable
        watchTransport.isReachable = reachable
    }

    /// Mirrors a workout session: the watch attaches it, then the phone, and their hellos connect both.
    func connectMirroring() {
        let (watch, phone) = FakeMirrorChannel.pair()
        watchChannel = watch
        phoneChannel = phone
        watchMirror.attach(watch)
        phoneMirror.attach(phone)
    }

    /// The mirrored session's link drops, and both sides hear it.
    func dropMirroring() {
        watchChannel?.isLinked = false
        phoneChannel?.isLinked = false
        watchChannel?.onDisconnect?()
        phoneChannel?.onDisconnect?()
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

extension XCTestCase {
    /// Broadlands with 120 extra bunkers of random outline on hole 1, so its start no longer fits in
    /// one message. Real courses fit since course outlines were stored compactly.
    func largeSelection() throws -> CourseSelection {
        let url = try XCTUnwrap(Bundle(for: SyncPair.self).url(forResource: "Broadlands-Golf-Course.json", withExtension: "gz"))
        var course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: url).gzipDecompressed())
        var random = SeededGenerator(seed: 7)
        let center = course.location.coordinate
        for index in 0..<120 {
            let polygon = CoordinatePath((0..<200).map { _ in
                Coordinate(lat: center.lat + random.uniform(-0.01...0.01), lon: center.lon + random.uniform(-0.01...0.01))
            })
            let bunker = Feature(id: course.nextFeatureID + index, type: .bunker, polygon: polygon)
            course.features.append(bunker)
            course.subCourses[0].holes[0].features.append(bunker.id)
        }
        let selection = CourseSelection(course: course, selectedSubCourseIndices: [0, 1])
        XCTAssertGreaterThan(try JSONEncoder().encode(selection.trimmed).gzipCompressed().count, SyncCodec.maxMessageBytes)
        return selection
    }
}
