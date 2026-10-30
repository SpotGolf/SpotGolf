import Foundation
import os

/// `SyncTransport` that sends over workout mirroring while it is connected, and over
/// WatchConnectivity otherwise. Queued messages, the context and files always go over
/// WatchConnectivity, which delivers them even if either app quits first.
@MainActor
final class RoutingTransport: SyncTransport {
    weak var delegate: SyncTransportDelegate?

    let mirror: MirrorTransport
    /// WatchConnectivity, or a fake in tests.
    let fallback: SyncTransport

    private enum Channel: String {
        case mirroring
        case watchConnectivity = "WatchConnectivity"
    }

    /// The channel of the last send, so a change is logged once.
    private var lastChannel: Channel?

    init(mirror: MirrorTransport, fallback: SyncTransport) {
        self.mirror = mirror
        self.fallback = fallback
        mirror.delegate = self
        fallback.delegate = self
    }

    var isReachable: Bool {
        mirror.isConnected || fallback.isReachable
    }

    var hasCounterpart: Bool {
        fallback.hasCounterpart
    }

    /// Over mirroring when connected. A send that fails because mirroring is down goes once
    /// over WatchConnectivity. A timeout fails as it is, since the other side may have it.
    func send(_ payload: [String: Any],
              reply: @escaping ([String: Any]) -> Void,
              failure: @escaping (Error) -> Void) {
        guard mirror.isConnected else {
            use(.watchConnectivity)
            fallback.send(payload, reply: reply, failure: failure)
            return
        }
        use(.mirroring)
        mirror.send(payload, reply: reply, failure: { [weak self] error in
            guard let self, case SyncTransportError.unreachable = error else {
                failure(error)
                return
            }
            self.use(.watchConnectivity)
            self.fallback.send(payload, reply: reply, failure: failure)
        })
    }

    private func use(_ channel: Channel) {
        guard channel != lastChannel else { return }
        lastChannel = channel
        Log.sync.notice("Sync channel: \(channel.rawValue)")
    }

    func queue(_ payload: [String: Any]) {
        fallback.queue(payload)
    }

    func updateContext(_ payload: [String: Any]) {
        fallback.updateContext(payload)
    }

    func transferFile(_ url: URL, metadata: [String: Any]) {
        fallback.transferFile(url, metadata: metadata)
    }

    var outstandingFileTransfers: [[String: Any]] {
        fallback.outstandingFileTransfers
    }
}

extension RoutingTransport: MirrorTransportDelegate {
    func mirror(didReceive payload: [String: Any]) -> [String: Any] {
        delegate?.transport(didReceive: payload) ?? [:]
    }

    func mirrorConnectionChanged() {
        delegate?.transportReachabilityChanged()
    }
}

extension RoutingTransport: SyncTransportDelegate {
    func transport(didReceive payload: [String: Any]) -> [String: Any] {
        delegate?.transport(didReceive: payload) ?? [:]
    }

    func transport(didReceiveQueued payload: [String: Any]) {
        delegate?.transport(didReceiveQueued: payload)
    }

    func transportReachabilityChanged() {
        delegate?.transportReachabilityChanged()
    }

    func transport(didReceiveFile url: URL, metadata: [String: Any]) {
        delegate?.transport(didReceiveFile: url, metadata: metadata)
    }

    func transport(didFinishFileTransfer metadata: [String: Any], error: Error?) {
        delegate?.transport(didFinishFileTransfer: metadata, error: error)
    }
}
