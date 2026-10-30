import Foundation
import os

/// What `MirrorTransport` needs from a mirrored workout session. Tests use a fake that
/// connects two transports, since mirroring does not run on simulators.
@MainActor
protocol MirrorChannel: AnyObject {
    /// Sends data to the other device's session. `completion` gets nil once it was sent, or
    /// the error. It may never be called.
    func send(_ data: Data, completion: @escaping (Error?) -> Void)

    /// Called with each piece of data from the other device.
    var onReceive: ((Data) -> Void)? { get set }

    /// Called when the link to the other device drops, or the session ends.
    var onDisconnect: (() -> Void)? { get set }

    /// Called when the session can never carry data again, like the phone's copy once it
    /// ended or disconnected. Only a new session, from the watch mirroring again, takes its place.
    var onEnd: (() -> Void)? { get set }
}

@MainActor
protocol MirrorTransportDelegate: AnyObject {
    /// A payload from the other device's `send`. Returns the reply payload.
    func mirror(didReceive payload: [String: Any]) -> [String: Any]
    func mirrorConnectionChanged()
}

/// One message over mirroring. Mirroring has no replies of its own, so each request gets a
/// reply envelope that names it.
struct MirrorEnvelope: Codable, Equatable {
    let id: UUID
    /// The request this answers. Nil for a request.
    let inReplyTo: UUID?
    /// A binary property list of the payload. Empty for a hello, or an empty reply.
    let payload: Data

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> MirrorEnvelope {
        try PropertyListDecoder().decode(MirrorEnvelope.self, from: data)
    }

    static func payloadData(_ payload: [String: Any]) throws -> Data {
        guard !payload.isEmpty else { return Data() }
        return try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
    }

    static func payload(from data: Data) -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }
}

/// Sends messages over the workout session mirrored between the watch and the phone, which
/// keeps working while the watch screen is off.
///
/// Same rules as `WatchConnectivityTransport`: one send in flight, later sends wait their turn,
/// and exactly one of `reply` or `failure` runs. A successful start of mirroring does not mean
/// the link works (on simulators every send fails), so the transport is connected only once
/// an envelope has arrived from the other side. Until then it sends a hello now and then.
@MainActor
final class MirrorTransport {
    /// How often a hello goes while attached and not connected.
    static let helloInterval: TimeInterval = 10

    weak var delegate: MirrorTransportDelegate?

    private(set) var isConnected = false {
        didSet {
            guard isConnected != oldValue else { return }
            disconnectedSince = isConnected ? nil : Date()
            Log.sync.notice("Mirroring connected: \(self.isConnected)")
            delegate?.mirrorConnectionChanged()
        }
    }

    /// When the transport last stopped being connected, or nil while connected or never connected.
    private(set) var disconnectedSince: Date?

    private(set) var channel: MirrorChannel?
    private let sendTimeout: TimeInterval
    private let maxWaiting: Int

    private struct PendingSend {
        let payload: [String: Any]
        let reply: ([String: Any]) -> Void
        let failure: (Error) -> Void
    }

    private struct InFlight {
        let id: UUID
        let finish: (Result<[String: Any], Error>) -> Void
    }

    private var waiting: [PendingSend] = []
    private var inFlight: InFlight?
    private var isSayingHello = false
    /// Whether the first hello's result since attaching or disconnecting was logged. Only the
    /// first is, since on simulators every hello fails, every helloInterval
    private var loggedFirstHello = false
    private var helloTimer: Timer?

    init(sendTimeout: TimeInterval = WatchConnectivityTransport.sendTimeout,
         maxWaiting: Int = WatchConnectivityTransport.maxWaiting) {
        self.sendTimeout = sendTimeout
        self.maxWaiting = maxWaiting
    }

    /// Uses `channel` from now on, in place of any earlier one.
    func attach(_ channel: MirrorChannel) {
        if self.channel != nil {
            disconnected()
        }
        self.channel = channel
        loggedFirstHello = false
        channel.onReceive = { [weak self, weak channel] data in
            guard let self, let channel, channel === self.channel else { return }
            self.receive(data)
        }
        channel.onDisconnect = { [weak self, weak channel] in
            guard let self, let channel, channel === self.channel else { return }
            Log.sync.notice("Mirroring disconnected")
            self.disconnected()
        }
        // Stops the hellos on a session that can't carry them any more
        channel.onEnd = { [weak self, weak channel] in
            guard let self, let channel, channel === self.channel else { return }
            self.detach()
        }
        Log.sync.notice("Mirroring attached")
        sayHello()
        startHelloTimer()
    }

    /// Stops using the channel, when its session ends.
    func detach() {
        guard channel != nil else { return }
        Log.sync.notice("Mirroring detached")
        channel = nil
        helloTimer?.invalidate()
        helloTimer = nil
        disconnected()
    }

    func send(_ payload: [String: Any],
              reply: @escaping ([String: Any]) -> Void,
              failure: @escaping (Error) -> Void) {
        guard channel != nil, isConnected else {
            failure(SyncTransportError.unreachable)
            return
        }
        waiting.append(PendingSend(payload: payload, reply: reply, failure: failure))
        if waiting.count > maxWaiting {
            waiting.removeFirst().failure(SyncTransportError.tooManyWaiting)
        }
        sendNext()
    }

    /// Sends a hello, whose reply connects the transport. Nothing happens while connected.
    func sayHello() {
        guard let channel, !isConnected, !isSayingHello else { return }
        let data: Data
        do {
            data = try MirrorEnvelope(id: UUID(), inReplyTo: nil, payload: Data()).encoded()
        } catch {
            Log.sync.error("Could not encode the mirroring hello: \(String(describing: error))")
            return
        }
        isSayingHello = true
        channel.send(data) { [weak self] error in
            guard let self else { return }
            self.isSayingHello = false
            guard !self.loggedFirstHello else { return }
            self.loggedFirstHello = true
            if let error {
                Log.sync.notice("First mirroring hello failed: \(String(describing: error))")
            } else {
                Log.sync.notice("First mirroring hello sent")
            }
        }
    }

    private func startHelloTimer() {
        guard helloTimer == nil else { return }
        helloTimer = Timer.scheduledTimer(withTimeInterval: Self.helloInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sayHello() }
        }
    }

    private func sendNext() {
        while inFlight == nil, !waiting.isEmpty {
            let next = waiting.removeFirst()
            guard let channel, isConnected else {
                next.failure(SyncTransportError.unreachable)
                continue
            }
            let id = UUID()
            let data: Data
            do {
                data = try MirrorEnvelope(id: id, inReplyTo: nil, payload: MirrorEnvelope.payloadData(next.payload)).encoded()
            } catch {
                next.failure(error)
                continue
            }

            // Exactly one of reply, error, timeout, or disconnect finishes the send
            var finished = false
            var timer: Timer?
            let finish: (Result<[String: Any], Error>) -> Void = { [weak self] result in
                guard !finished else { return }
                finished = true
                timer?.invalidate()
                if self?.inFlight?.id == id {
                    self?.inFlight = nil
                }
                switch result {
                case .success(let response): next.reply(response)
                case .failure(let error): next.failure(error)
                }
                self?.sendNext()
            }
            inFlight = InFlight(id: id, finish: finish)
            timer = Timer.scheduledTimer(withTimeInterval: sendTimeout, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let inFlight = self.inFlight, inFlight.id == id else { return }
                    inFlight.finish(.failure(SyncTransportError.timedOut))
                }
            }
            channel.send(data) { [weak self] error in
                guard let error, let self else { return }
                Log.sync.notice("Mirroring send failed: \(String(describing: error))")
                // The link is down, so the send never arrived
                if self.inFlight?.id == id {
                    self.inFlight?.finish(.failure(SyncTransportError.unreachable))
                }
                self.disconnected()
            }
        }
    }

    private func receive(_ data: Data) {
        let envelope: MirrorEnvelope
        do {
            envelope = try MirrorEnvelope.decoded(from: data)
        } catch {
            Log.sync.error("Could not decode a mirroring envelope: \(String(describing: error))")
            return
        }
        isConnected = true
        if let request = envelope.inReplyTo {
            guard let inFlight, inFlight.id == request else { return }
            inFlight.finish(.success(MirrorEnvelope.payload(from: envelope.payload)))
            return
        }
        // A hello is answered and goes no further
        var response: [String: Any] = [:]
        if !envelope.payload.isEmpty {
            response = delegate?.mirror(didReceive: MirrorEnvelope.payload(from: envelope.payload)) ?? [:]
        }
        sendReply(response, to: envelope.id)
    }

    private func sendReply(_ response: [String: Any], to request: UUID) {
        guard let channel else { return }
        do {
            let data = try MirrorEnvelope(id: UUID(), inReplyTo: request,
                                          payload: MirrorEnvelope.payloadData(response)).encoded()
            channel.send(data) { [weak self] error in
                guard let error else { return }
                Log.sync.notice("Mirroring reply failed: \(String(describing: error))")
                self?.disconnected()
            }
        } catch {
            Log.sync.error("Could not encode a mirroring reply: \(String(describing: error))")
        }
    }

    /// The link is down: every send waiting or in flight fails, and a hello reconnects.
    private func disconnected() {
        isSayingHello = false
        loggedFirstHello = false
        let failed = waiting
        waiting = []
        let current = inFlight
        inFlight = nil
        isConnected = false
        current?.finish(.failure(SyncTransportError.unreachable))
        for send in failed {
            send.failure(SyncTransportError.unreachable)
        }
    }
}
