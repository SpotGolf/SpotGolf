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
                .onAppear {
                    if CommandLine.arguments.contains("--ui-testing") {
                        roundStore.rounds = []
                    }
                    syncService.roundStore = roundStore
                    syncService.guessStore = guessStore
                    syncService.settingsStore = settingsStore
                    locationManager.requestPermission()
                }
        }
    }
}
