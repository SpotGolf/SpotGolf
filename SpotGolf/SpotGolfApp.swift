import SwiftUI

@main
struct SpotGolfApp: App {
    @StateObject private var roundStore = RoundStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var syncService = SyncService()
    @StateObject private var courseService = CourseService()
    @StateObject private var guessStore = GuessStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var trackStore = TrackStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .environmentObject(syncService)
                .environmentObject(courseService)
                .environmentObject(guessStore)
                .environmentObject(settingsStore)
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
                    locationManager.requestPermission()
                    Task {
                        await courseService.refreshIndex()
                    }
                }
                .onChange(of: roundStore.activeRound?.id) {
                    trackStore.flush()
                }
                .onChange(of: scenePhase) {
                    if scenePhase != .active {
                        trackStore.flush()
                    }
                }
        }
    }

    /// Stores every GPS fix that arrives while a round is active.
    @MainActor
    private func recordTrack() {
        let rounds = roundStore
        let tracks = trackStore
        locationManager.onRawLocations = { locations in
            guard let round = rounds.activeRound else { return }
            tracks.append(locations, roundID: round.id)
        }
    }
}
