import Foundation
import os
import WatchConnectivity

/// What `SyncService` needs from WatchConnectivity. Tests use a fake that connects two services.
@MainActor
protocol SyncTransport: AnyObject {
    var delegate: SyncTransportDelegate? { get set }

    /// The other app can receive `send` right now.
    var isReachable: Bool { get }

    /// A counterpart app exists: on the phone, a paired watch with the app installed.
    var hasCounterpart: Bool { get }

    /// Sends right away. Exactly one of `reply` or `failure` is called.
    func send(_ payload: [String: Any],
              reply: @escaping ([String: Any]) -> Void,
              failure: @escaping (Error) -> Void)

    /// Queues for delivery in order, even if either app quits first.
    func queue(_ payload: [String: Any])

    /// Replaces the latest state the other app receives.
    func updateContext(_ payload: [String: Any])
}

@MainActor
protocol SyncTransportDelegate: AnyObject {
    /// A payload from `send`. Returns the reply payload.
    func transport(didReceive payload: [String: Any]) -> [String: Any]
    /// A payload from `queue` or `updateContext`. No reply.
    func transport(didReceiveQueued payload: [String: Any])
    func transportReachabilityChanged()
}

/// `SyncTransport` over the default `WCSession`.
///
/// Only one `sendMessage` is in flight at a time; later sends wait their turn. The watch app
/// crashed inside WatchConnectivity's own reply timeout handling
/// (`-[WCQueuedMessage timeoutTimer]: unrecognized selector`) after hours of many messages
/// in flight, so the transport keeps WatchConnectivity's queue as short as it can.
@MainActor
final class WatchConnectivityTransport: NSObject, SyncTransport {
    /// A send with no reply or error after this long counts as failed, so the next can go.
    static let sendTimeout: TimeInterval = 30

    /// Sends waiting beyond this many fail, oldest first.
    static let maxWaiting = 20

    weak var delegate: SyncTransportDelegate?

    let session: WCSession?

    private struct PendingSend {
        let payload: [String: Any]
        let reply: ([String: Any]) -> Void
        let failure: (Error) -> Void
    }

    private var waiting: [PendingSend] = []
    private var isSending = false

    /// Called with each file the other app sent, already moved to a place of this app's own,
    /// and the metadata it was sent with. The file is the receiver's to move or delete.
    var onFileReceived: ((URL, [String: Any]?) -> Void)?

    /// Called when a `transferFile` finishes, with the file, its metadata, and the error if it failed.
    var onFileTransferFinished: ((URL, [String: Any]?, Error?) -> Void)?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    var isActivated: Bool {
        session?.activationState == .activated
    }

    var isReachable: Bool {
        isActivated && session?.isReachable == true
    }

    func send(_ payload: [String: Any],
              reply: @escaping ([String: Any]) -> Void,
              failure: @escaping (Error) -> Void) {
        guard session != nil, isReachable else {
            failure(SyncTransportError.unreachable)
            return
        }
        waiting.append(PendingSend(payload: payload, reply: reply, failure: failure))
        if waiting.count > Self.maxWaiting {
            waiting.removeFirst().failure(SyncTransportError.tooManyWaiting)
        }
        sendNext()
    }

    private func sendNext() {
        while !isSending, !waiting.isEmpty {
            let next = waiting.removeFirst()
            guard let session, isReachable else {
                next.failure(SyncTransportError.unreachable)
                continue
            }
            isSending = true

            // Exactly one of reply, error, or timeout finishes the send
            var finished = false
            var timer: Timer?
            let finish: (Result<[String: Any], Error>) -> Void = { [weak self] result in
                guard !finished else { return }
                finished = true
                timer?.invalidate()
                switch result {
                case .success(let response): next.reply(response)
                case .failure(let error): next.failure(error)
                }
                self?.isSending = false
                self?.sendNext()
            }
            let sendableFinish = SendableFinish(finish)
            timer = Timer.scheduledTimer(withTimeInterval: Self.sendTimeout, repeats: false) { _ in
                Task { @MainActor in sendableFinish.handler(.failure(SyncTransportError.timedOut)) }
            }
            session.sendMessage(next.payload, replyHandler: { response in
                let payload = SendablePayload(response)
                Task { @MainActor in sendableFinish.handler(.success(payload.value)) }
            }, errorHandler: { error in
                Task { @MainActor in sendableFinish.handler(.failure(error)) }
            })
        }
    }

    /// Sends still waiting can't go while the other app is unreachable.
    private func failWaiting() {
        let failed = waiting
        waiting = []
        for send in failed {
            send.failure(SyncTransportError.unreachable)
        }
    }

    func queue(_ payload: [String: Any]) {
        guard let session, isActivated else {
            Log.sync.error("Queued message dropped: WCSession not activated")
            return
        }
        session.transferUserInfo(payload)
    }

    func updateContext(_ payload: [String: Any]) {
        guard let session, isActivated else {
            Log.sync.error("Context update dropped: WCSession not activated")
            return
        }
        do {
            try session.updateApplicationContext(payload)
        } catch {
            Log.sync.error("Could not update application context: \(String(describing: error), privacy: .public)")
        }
    }

    /// Queues a file for the other app. It is sent in the background, even if this app quits,
    /// and `onFileTransferFinished` says when it arrived. Returns false if it could not be queued.
    @discardableResult
    func transferFile(_ url: URL, metadata: [String: Any]) -> Bool {
        guard let session, isActivated else {
            Log.sync.error("File transfer dropped: WCSession not activated")
            return false
        }
        session.transferFile(url, metadata: metadata)
        return true
    }

    /// The files queued with `transferFile` that have not arrived yet.
    var outstandingFileTransferURLs: [URL] {
        session?.outstandingFileTransfers.map(\.file.fileURL) ?? []
    }
}

enum SyncTransportError: Error {
    case unreachable
    case timedOut
    case tooManyWaiting
}

extension WatchConnectivityTransport: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Log.sync.error("WCSession activation failed: \(String(describing: error), privacy: .public)")
        } else {
            Log.sync.notice("WCSession activated, state \(activationState.rawValue, privacy: .public)")
        }
        Task { @MainActor in
            self.delegate?.transportReachabilityChanged()
            // A context that arrived before activation is not delivered again
            if !session.receivedApplicationContext.isEmpty {
                self.delegate?.transport(didReceiveQueued: session.receivedApplicationContext)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachabilityChanged() }
    }

    func reachabilityChanged() {
        Log.sync.notice("Reachable: \(self.isReachable, privacy: .public)")
        if !isReachable {
            failWaiting()
        }
        delegate?.transportReachabilityChanged()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let payload = SendablePayload(message)
        let reply = SendableReply(replyHandler)
        Task { @MainActor in
            let response = self.delegate?.transport(didReceive: payload.value) ?? [:]
            reply.handler(response)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = SendablePayload(message)
        Task { @MainActor in _ = self.delegate?.transport(didReceive: payload.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = SendablePayload(userInfo)
        Task { @MainActor in self.delegate?.transport(didReceiveQueued: payload.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let payload = SendablePayload(applicationContext)
        Task { @MainActor in self.delegate?.transport(didReceiveQueued: payload.value) }
    }

    /// The file is deleted once this returns, so it is moved out of the way first.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let inbox = FileManager.default.temporaryDirectory.appendingPathComponent("received-files", isDirectory: true)
        let destination = inbox.appendingPathComponent(UUID().uuidString + "-" + file.fileURL.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
        } catch {
            Log.sync.error("Could not keep received file \(file.fileURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        let received = SendableFile(url: destination, metadata: file.metadata, error: nil)
        Task { @MainActor in self.onFileReceived?(received.url, received.metadata) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let finished = SendableFile(url: fileTransfer.file.fileURL, metadata: fileTransfer.file.metadata, error: error)
        Task { @MainActor in self.onFileTransferFinished?(finished.url, finished.metadata, finished.error) }
    }
}

// A received or sent file: a URL, property-list metadata, and an error, all safe to pass between threads
private struct SendableFile: @unchecked Sendable {
    let url: URL
    let metadata: [String: Any]?
    let error: Error?
}

// WatchConnectivity payloads hold only property-list values, which are safe to pass between threads
private struct SendablePayload: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}

// Only ever called on the main actor
private struct SendableFinish: @unchecked Sendable {
    let handler: (Result<[String: Any], Error>) -> Void
    init(_ handler: @escaping (Result<[String: Any], Error>) -> Void) { self.handler = handler }
}

private struct SendableReply: @unchecked Sendable {
    let handler: ([String: Any]) -> Void
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
}
