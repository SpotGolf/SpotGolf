import SwiftUI

@main
struct SpotGolfWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchRoundView()
                .environmentObject(appDelegate.roundStore)
                .environmentObject(appDelegate.locationManager)
                .environmentObject(appDelegate.syncService)
                .environmentObject(appDelegate.watchSync)
                .environmentObject(appDelegate.workoutManager)
                .environmentObject(appDelegate.holeAdvance)
        }
    }
}
