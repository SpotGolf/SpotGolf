import SwiftUI

@main
struct SpotGolfApp: App {
    @StateObject private var roundStore = RoundStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var syncService = SyncService()
    @StateObject private var courseService = CourseService()
    @StateObject private var guessStore = GuessStore()
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .environmentObject(syncService)
                .environmentObject(courseService)
                .environmentObject(guessStore)
                .environmentObject(settingsStore)
                .onAppear {
                    if CommandLine.arguments.contains("--ui-testing") {
                        roundStore.rounds = []
                    }
                    syncService.roundStore = roundStore
                    syncService.guessStore = guessStore
                    syncService.settingsStore = settingsStore
                    locationManager.requestPermission()
                    Task {
                        await courseService.refreshIndex()
                    }
                }
        }
    }
}
