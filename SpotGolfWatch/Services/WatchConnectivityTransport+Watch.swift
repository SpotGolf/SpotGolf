import WatchConnectivity

/// The watch's side of `WatchConnectivityTransport`.
extension WatchConnectivityTransport {
    /// The phone is always there once the session is active.
    var hasCounterpart: Bool {
        isActivated
    }
}
