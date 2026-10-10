import Foundation
import Observation
import os

/// The one place messages go in and out. It encodes messages, splits large ones into chunks
/// and joins them back, and hands every incoming message to `handler`. What to send and
/// how to answer is decided by `PhoneSync` or `WatchSync`.
@MainActor
@Observable
final class SyncService {
    /// How long the phone waits for the watch to confirm a round start before offering Retry.
    nonisolated static let startTimeout: TimeInterval = 15

    /// The other app can receive messages right now.
    private(set) var isConnected = false

    /// A counterpart app exists: on the phone, a paired watch with the app installed.
    private(set) var hasCounterpart = false

    var syncError: String?

    let transport: SyncTransport

    /// Answers an incoming message. The returned message is the reply.
    @ObservationIgnored var handler: ((SyncMessage) -> SyncMessage?)?

    @ObservationIgnored private var reachabilityObservers: [() -> Void] = []
    @ObservationIgnored private var assembler = ChunkAssembler()

    init(transport: SyncTransport? = nil) {
        self.transport = transport ?? WatchConnectivityTransport()
        self.transport.delegate = self
        updateStatus()
    }

    /// Calls `observer` every time reachability or pairing changes.
    func onReachabilityChange(_ observer: @escaping () -> Void) {
        reachabilityObservers.append(observer)
    }

    /// Sends a message now, split into chunks when it is too large. `reply` gets the first
    /// reply that holds a message. `failure` is called once if any part fails, or if every
    /// part was answered and no answer held a message. So one of them is always called.
    func send(_ message: SyncMessage,
              reply: ((SyncMessage) -> Void)? = nil,
              failure: ((Error) -> Void)? = nil) {
        let payloads: [[String: Any]]
        do {
            payloads = try SyncCodec.payloads(for: message)
        } catch {
            Log.sync.error("Could not encode \(message.name): \(String(describing: error))")
            failure?(error)
            return
        }

        var answered = false
        var unanswered = payloads.count
        for payload in payloads {
            transport.send(payload, reply: { response in
                unanswered -= 1
                guard !answered else { return }
                guard let message = SyncCodec.message(in: response) else {
                    if unanswered == 0 {
                        answered = true
                        failure?(SyncServiceError.noReply)
                    }
                    return
                }
                answered = true
                reply?(message)
            }, failure: { error in
                // Out of range is normal, so it is not an error
                if case SyncTransportError.unreachable = error {
                    Log.sync.notice("Send \(message.name) failed: unreachable")
                } else {
                    Log.sync.error("Send \(message.name) failed: \(String(describing: error))")
                }
                guard !answered else { return }
                answered = true
                failure?(error)
            })
        }
    }

    /// Queues a message for delivery even when the other app is not reachable.
    func queue(_ message: SyncMessage) {
        do {
            transport.queue(try SyncCodec.payload(message))
        } catch {
            Log.sync.error("Could not encode queued \(message.name): \(String(describing: error))")
        }
    }

    /// Replaces the latest state the other app receives.
    func updateContext(_ context: SyncContext) {
        do {
            transport.updateContext(try SyncCodec.payload(.context(context)))
        } catch {
            Log.sync.error("Could not encode context: \(String(describing: error))")
        }
    }

    private func updateStatus() {
        isConnected = transport.isReachable
        hasCounterpart = transport.hasCounterpart
    }

    private func receive(_ message: SyncMessage) -> SyncMessage? {
        if case .chunk(let chunk) = message {
            guard let whole = assembler.add(chunk) else { return nil }
            return handler?(whole)
        }
        return handler?(message)
    }
}

enum SyncServiceError: Error {
    /// The other app answered without a message.
    case noReply
}

extension SyncService: SyncTransportDelegate {
    func transport(didReceive payload: [String: Any]) -> [String: Any] {
        guard let message = SyncCodec.message(in: payload),
              let reply = receive(message) else { return [:] }
        do {
            return try SyncCodec.payload(reply)
        } catch {
            Log.sync.error("Could not encode reply \(reply.name): \(String(describing: error))")
            return [:]
        }
    }

    func transport(didReceiveQueued payload: [String: Any]) {
        guard let message = SyncCodec.message(in: payload) else { return }
        _ = receive(message)
    }

    func transportReachabilityChanged() {
        updateStatus()
        for observer in reachabilityObservers {
            observer()
        }
    }
}
