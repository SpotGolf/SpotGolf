import SwiftUI

@main
struct SpotGolfWatchApp: App {
    @StateObject private var roundStore = RoundStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var syncService = SyncService()
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var guessStore = GuessStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var breadcrumbRecorder = BreadcrumbRecorder()
    @StateObject private var swingDetector = SwingDetector()
    @StateObject private var trackStore = TrackStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRoundView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .environmentObject(syncService)
                .environmentObject(workoutManager)
                .environmentObject(guessStore)
                .environmentObject(settingsStore)
                .environmentObject(breadcrumbRecorder)
                .environmentObject(swingDetector)
                .environmentObject(trackStore)
                .onAppear {
                    if CommandLine.arguments.contains("--ui-testing") {
                        roundStore.rounds = []
                    }
                    syncService.roundStore = roundStore
                    syncService.guessStore = guessStore
                    syncService.settingsStore = settingsStore
                    syncService.trackStore = trackStore
                    recordTrack()
                    syncService.sendPendingTracks()
                    locationManager.requestPermission()
                }
                .onChange(of: roundStore.activeRound?.id) {
                    trackStore.flush()
                    syncService.sendPendingTracks()
                }
                .onChange(of: scenePhase) {
                    if scenePhase != .active {
                        trackStore.flush()
                    }
                }
        }
    }

    /// Stores every GPS fix that arrives while a round is active, and regularly
    /// ships segments to the phone so it can draw the path live.
    @MainActor
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
