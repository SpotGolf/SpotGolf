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
        case .addMark(let mark, let holeIndex, let roundID):
            guard let data = try? JSONEncoder().encode(mark) else { return }
            payload = [
                "type": "addMark",
                "roundId": roundID.uuidString,
                "holeIndex": holeIndex,
                "mark": data
            ]
        case .setCourse(let selection, let roundID):
            guard let data = try? JSONEncoder().encode(selection) else { return }
            payload = [
                "type": "setCourse",
                "roundId": roundID.uuidString,
                "courseSelection": data
            ]
        case .setMarkType(let markID, let markType, let roundID):
            payload = [
                "type": "setMarkType",
                "markId": markID.uuidString,
                "markType": markType.rawValue,
                "roundId": roundID.uuidString
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
                  let holeIndex = message["holeIndex"] as? Int,
                  let mark = try? JSONDecoder().decode(BallMark.self, from: data) else { return }
            roundStore?.addMark(to: roundID, holeIndex: holeIndex, mark: mark, fromSync: true)

        case "setCourse":
            guard let data = message["courseSelection"] as? Data,
                  let idString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: idString),
                  let selection = try? JSONDecoder().decode(CourseSelection.self, from: data) else { return }
            roundStore?.setCourse(selection, for: roundID, fromSync: true)

        case "setMarkType":
            guard let markIdString = message["markId"] as? String,
                  let markID = UUID(uuidString: markIdString),
                  let typeString = message["markType"] as? String,
                  let markType = BallMarkType(rawValue: typeString),
                  let roundIdString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: roundIdString) else { return }
            roundStore?.setMarkType(markID: markID, type: markType, in: roundID, fromSync: true)

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
