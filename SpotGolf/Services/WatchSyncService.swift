import Foundation
import WatchConnectivity

@MainActor
class WatchSyncService: NSObject, ObservableObject {
    var roundStore: RoundStore?

    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
}

extension WatchSyncService: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation failed: \(error)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["ballMark"] as? Data else { return }
        do {
            let mark = try JSONDecoder().decode(BallMark.self, from: data)
            Task { @MainActor in
                self.roundStore?.addMark(mark)
            }
        } catch {
            print("Failed to decode ball mark from watch: \(error)")
        }
    }
}
