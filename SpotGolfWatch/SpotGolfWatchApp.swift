import SwiftUI

@main
struct SpotGolfWatchApp: App {
    @StateObject private var roundStore = RoundStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var phoneSync = PhoneSyncService()

    var body: some Scene {
        WindowGroup {
            WatchRoundView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .onAppear {
                    phoneSync.roundStore = roundStore
                    locationManager.requestPermission()
                }
        }
    }
}
