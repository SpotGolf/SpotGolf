import Combine
import WatchKit

/// Owns the services that record a round, so recording resumes as soon as the app
/// launches, even when watchOS relaunches it in the background after a crash and
/// no view appears.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let roundStore = RoundStore()
    let locationManager = LocationManager()
    let syncService = SyncService()
    let workoutManager = WorkoutManager()
    let guessStore = GuessStore()
    let settingsStore = SettingsStore()
    // Every fix goes to disk as it arrives, so a crash loses none that were recorded
    let trackStore = TrackStore(flushThreshold: 1)

    private var activeRoundObserver: AnyCancellable?

    func applicationDidFinishLaunching() {
        // UI tests pass --keep-rounds when relaunching mid-round to test recovery
        if CommandLine.arguments.contains("--ui-testing"),
           !CommandLine.arguments.contains("--keep-rounds") {
            roundStore.rounds = []
        }
        syncService.roundStore = roundStore
        syncService.guessStore = guessStore
        syncService.settingsStore = settingsStore
        syncService.trackStore = trackStore
        recordTrack()
        syncService.sendPendingTracks()
        locationManager.requestPermission()

        activeRoundObserver = roundStore.$rounds
            .map { $0.first(where: \.isActive)?.id }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                trackStore.flush()
                syncService.sendPendingTracks()
            }

        resumeActiveRound()
    }

    /// watchOS relaunches the app here when it quit while a workout was running.
    func handleActiveWorkoutRecovery() {
        workoutManager.start()
        resumeActiveRound()
    }

    /// Restarts GPS and the workout for a round that was active when the app last quit.
    private func resumeActiveRound() {
        guard roundStore.activeRound != nil else { return }
        locationManager.startUpdating()
        workoutManager.start()
    }

    /// Stores every GPS fix that arrives while a round is active, and regularly
    /// ships segments to the phone so it can draw the path live.
    private func recordTrack() {
        let rounds = roundStore
        let tracks = trackStore
        let sync = syncService
        locationManager.onRawLocations = { locations in
            guard let round = rounds.activeRound else { return }
            tracks.append(locations, roundID: round.id)
            sync.sendPendingTracksIfDue()
        }
    }
}
