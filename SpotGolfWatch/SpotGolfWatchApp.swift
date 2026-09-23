import SwiftUI

@main
struct SpotGolfWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @StateObject private var breadcrumbRecorder = BreadcrumbRecorder()
    @StateObject private var swingDetector = SwingDetector()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRoundView()
                .environmentObject(appDelegate.roundStore)
                .environmentObject(appDelegate.locationManager)
                .environmentObject(appDelegate.syncService)
                .environmentObject(appDelegate.workoutManager)
                .environmentObject(appDelegate.guessStore)
                .environmentObject(appDelegate.settingsStore)
                .environmentObject(breadcrumbRecorder)
                .environmentObject(swingDetector)
                .environmentObject(appDelegate.trackStore)
                .onChange(of: scenePhase) {
                    if scenePhase != .active {
                        appDelegate.trackStore.flush()
                    }
                }
        }
    }
}
