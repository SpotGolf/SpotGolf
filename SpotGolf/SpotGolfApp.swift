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
                    locationManager.requestPermission()
                    Task {
                        await courseService.refreshIndex()
                    }
                }
        }
    }
}
