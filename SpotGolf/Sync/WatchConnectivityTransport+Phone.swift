import WatchConnectivity

/// The phone's side of `WatchConnectivityTransport`.
extension WatchConnectivityTransport {
    /// A paired watch with the app installed.
    var hasCounterpart: Bool {
        guard let session, isActivated else { return false }
        return session.isPaired && session.isWatchAppInstalled
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Log.sync.notice("WCSession deactivated; activating again")
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachabilityChanged() }
    }
}
