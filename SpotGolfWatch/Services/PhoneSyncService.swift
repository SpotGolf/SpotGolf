import Foundation
import WatchConnectivity

@MainActor
class PhoneSyncService: NSObject, ObservableObject {
    var roundStore: RoundStore? {
        didSet { bindSyncHandler() }
    }

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
        guard let session, session.activationState == .activated else { return }

        let payload: [String: Any]
        switch message {
        case .startRound(let id, let date):
            payload = [
                "type": "startRound",
                "id": id.uuidString,
                "date": ISO8601DateFormatter().string(from: date)
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
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("Failed to send sync message to phone: \(error)")
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
}

extension PhoneSyncService: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation failed: \(error)")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleMessage(userInfo)
    }

    private func handleMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        Task { @MainActor in
            switch type {
            case "startRound":
                guard let idString = message["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let dateString = message["date"] as? String,
                      let date = ISO8601DateFormatter().date(from: dateString) else { return }
                self.roundStore?.startRound(id: id, date: date, fromSync: true)

            case "endRound":
                guard let idString = message["id"] as? String,
                      let id = UUID(uuidString: idString) else { return }
                self.roundStore?.endRound(roundID: id, fromSync: true)

            case "addMark":
                guard let data = message["mark"] as? Data,
                      let idString = message["roundId"] as? String,
                      let roundID = UUID(uuidString: idString),
                      let mark = try? JSONDecoder().decode(BallMark.self, from: data) else { return }
                self.roundStore?.addMark(to: roundID, mark: mark, fromSync: true)

            default:
                break
            }
        }
    }
}
