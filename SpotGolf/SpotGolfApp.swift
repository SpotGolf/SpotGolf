import SwiftUI

@main
struct SpotGolfApp: App {
    @StateObject private var roundStore = RoundStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var watchSync = WatchSyncService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .onAppear {
                    if CommandLine.arguments.contains("--ui-testing") {
                        roundStore.rounds = []
                    }
                    watchSync.roundStore = roundStore
                    locationManager.requestPermission()
                }
        }
    }
}
