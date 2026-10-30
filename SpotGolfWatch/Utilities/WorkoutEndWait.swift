import Foundation
import os

/// Stops the workout after a round ends. Mirroring runs only while the workout does, so the
/// workout keeps running until the phone has the round's whole stream, which also means it
/// has the end, or for `maxWait` at most. Then WatchConnectivity finishes the job, as it does
/// for a phone out of range.
@MainActor
final class WorkoutEndWait {
    static let maxWait: TimeInterval = 60

    /// The ended round waited on.
    private(set) var roundID: UUID?

    private let maxWait: TimeInterval
    private let stop: () -> Void

    init(maxWait: TimeInterval = WorkoutEndWait.maxWait, stop: @escaping () -> Void) {
        self.maxWait = maxWait
        self.stop = stop
    }

    /// The round ended. `hasStream` says the watch still holds records of it the phone may lack.
    func roundEnded(_ roundID: UUID, hasStream: Bool) {
        guard hasStream else {
            self.roundID = nil
            stop()
            return
        }
        Log.workout.notice("Round ended; the workout runs until the phone has the stream, \(Int(self.maxWait)) s at most")
        self.roundID = roundID
        let wait = maxWait
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, self.roundID == roundID else { return }
            Log.workout.notice("The phone did not get the whole stream in \(Int(wait)) s; stopping the workout")
            self.finish()
        }
    }

    /// The phone has the whole stream of `roundID`, so its stream was deleted.
    func streamComplete(_ roundID: UUID) {
        guard self.roundID == roundID else { return }
        Log.workout.notice("The phone has the ended round's stream; stopping the workout")
        finish()
    }

    /// A new round needs the workout, so it is not stopped.
    func cancel() {
        roundID = nil
    }

    private func finish() {
        roundID = nil
        stop()
    }
}
