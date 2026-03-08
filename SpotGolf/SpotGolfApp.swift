import SwiftUI

@main
struct SpotGolfApp: App {
    @StateObject private var roundStore = RoundStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var syncService = SyncService()
    @StateObject private var courseService = CourseService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .environmentObject(syncService)
                .environmentObject(courseService)
                .onAppear {
                    if CommandLine.arguments.contains("--ui-testing") {
                        roundStore.rounds = []
                    }
                    syncService.roundStore = roundStore
                    locationManager.requestPermission()
                    Task {
                        await courseService.refreshIndex()
                    }
                }
        }
    }
}
