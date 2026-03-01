import Foundation
import WatchConnectivity

@MainActor
class PhoneSyncService: NSObject, ObservableObject {
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

    func sendMark(_ mark: BallMark) {
        guard let session, session.isReachable else { return }
        do {
            let data = try JSONEncoder().encode(mark)
            session.sendMessage(["ballMark": data], replyHandler: nil) { error in
                print("Failed to send mark to phone: \(error)")
            }
        } catch {
            print("Failed to encode ball mark: \(error)")
        }
    }
}

extension PhoneSyncService: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation failed: \(error)")
        }
    }
}
