import Foundation
import WatchConnectivity

private let syncDateFormatter = ISO8601DateFormatter()

@MainActor
class SyncService: NSObject, ObservableObject {

    var roundStore: RoundStore? {
        didSet { bindSyncHandler() }
    }

    @Published var isConnected = false

    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    private func bindSyncHandler() {
        roundStore?.onSyncEvent = { [weak self] message in
            self?.send(message)
        }
    }

    private nonisolated func send(_ message: SyncMessage) {
        Task { @MainActor in
            self.sendOnMain(message)
        }
    }

    private func sendOnMain(_ message: SyncMessage) {
        guard let session, session.activationState == .activated else {
            print("[Sync] Cannot send – session not activated")
            return
        }

        let payload: [String: Any]
        switch message {
        case .startRound(let id, let date):
            payload = [
                "type": "startRound",
                "id": id.uuidString,
                "date": syncDateFormatter.string(from: date)
            ]
        case .endRound(let id):
            payload = [
                "type": "endRound",
                "id": id.uuidString
            ]
        case .addMark(let mark, let roundID):
            guard let data = try? JSONEncoder().encode(mark) else { return }
            payload = [
                "type": "addMark",
                "roundId": roundID.uuidString,
                "mark": data
            ]
        case .nextHole(let id):
            payload = [
                "type": "nextHole",
                "id": id.uuidString
            ]
        case .previousHole(let id):
            payload = [
                "type": "previousHole",
                "id": id.uuidString
            ]
        }

        session.transferUserInfo(payload)
    }

    func handleMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        switch type {
        case "startRound":
            guard let idString = message["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let dateString = message["date"] as? String,
                  let date = syncDateFormatter.date(from: dateString) else { return }
            roundStore?.startRound(id: id, date: date, fromSync: true)

        case "endRound":
            guard let idString = message["id"] as? String,
                  let id = UUID(uuidString: idString) else { return }
            roundStore?.endRound(roundID: id, fromSync: true)

        case "addMark":
            guard let data = message["mark"] as? Data,
                  let idString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: idString),
                  let mark = try? JSONDecoder().decode(BallMark.self, from: data) else { return }
            roundStore?.addMark(to: roundID, mark: mark, fromSync: true)

        case "nextHole":
            guard let idString = message["id"] as? String,
                  let id = UUID(uuidString: idString) else { return }
            roundStore?.nextHole(roundID: id, fromSync: true)

        case "previousHole":
            guard let idString = message["id"] as? String,
                  let id = UUID(uuidString: idString) else { return }
            roundStore?.previousHole(roundID: id, fromSync: true)

        default:
            break
        }
    }

    private func updateConnectionStatus() {
        guard let session else {
            isConnected = false
            return
        }
        isConnected = session.activationState == .activated && session.isReachable
    }
}

extension SyncService: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[Sync] WCSession activation failed: \(error)")
        } else {
            print("[Sync] WCSession activated – state: \(activationState.rawValue), reachable: \(session.isReachable)")
        }
        Task { @MainActor in self.updateConnectionStatus() }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handleMessage(message) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handleMessage(userInfo) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        print("[Sync] Reachability changed: \(session.isReachable)")
        Task { @MainActor in self.updateConnectionStatus() }
    }
}
