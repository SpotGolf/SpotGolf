import Foundation
import HealthKit

/// `MirrorChannel` over a workout session mirrored between the watch and the phone. The
/// session's delegate passes on what arrives with `received(_:)` and `disconnected()`: on the
/// watch that is `WorkoutManager`, and on the phone the channel itself.
@MainActor
final class WorkoutSessionChannel: NSObject, MirrorChannel {
    let session: HKWorkoutSession

    var onReceive: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onEnd: (() -> Void)?

    init(session: HKWorkoutSession) {
        self.session = session
    }

    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        let finish = SendableCompletion(completion)
        // HealthKit calls this on its own queue. It must be @Sendable: a plain closure made
        // here would count as main-actor code, and Swift 6 traps when it runs anywhere else.
        session.sendToRemoteWorkoutSession(data: data) { @Sendable success, error in
            let failure = success ? nil : SendableError(error ?? SyncTransportError.unreachable)
            Task { @MainActor in finish.handler(failure?.error) }
        }
    }

    func received(_ data: [Data]) {
        for item in data {
            onReceive?(item)
        }
    }

    func disconnected() {
        onDisconnect?()
    }

    // The phone's mirrored session never reconnects once it ends or disconnects
    private func sessionEnded() {
        disconnected()
        onEnd?()
    }
}

/// The phone's mirrored sessions end when the watch ends them, or drop when the link does.
extension WorkoutSessionChannel: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState,
                                     date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.sessionEnded() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Log.sync.error("Mirrored workout session failed: \(String(describing: error))")
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.received(data) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didDisconnectFromRemoteDeviceWithError error: Error?) {
        Log.sync.notice("Mirrored workout session disconnected: \(String(describing: error))")
        Task { @MainActor in self.sessionEnded() }
    }
}

// Only ever called on the main actor
private struct SendableCompletion: @unchecked Sendable {
    let handler: (Error?) -> Void
    init(_ handler: @escaping (Error?) -> Void) { self.handler = handler }
}

// An error from HealthKit, only read on the main actor
private struct SendableError: @unchecked Sendable {
    let error: Error
    init(_ error: Error) { self.error = error }
}
