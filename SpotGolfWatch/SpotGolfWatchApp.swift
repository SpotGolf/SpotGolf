import SwiftUI

@main
struct SpotGolfWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(appDelegate.roundStore)
                .environment(appDelegate.locationManager)
                .environment(appDelegate.syncService)
                .environment(appDelegate.watchSync)
                .environment(appDelegate.workoutManager)
                .environment(appDelegate.permissions)
                .environment(appDelegate.puttCapture)
                .environment(appDelegate.captureUploader)
                .environment(appDelegate.contactMonitor)
        }
    }
}

/// The permissions screen until every permission is granted, then the round screen. A round
/// already recording stays on screen, so it can still be ended.
private struct WatchRootView: View {
    @Environment(PermissionChecker.self) private var permissions
    @Environment(RoundStore.self) private var roundStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if permissions.allGranted || roundStore.activeRound != nil {
                WatchRoundView()
            } else {
                PermissionsView()
            }
        }
        // Permissions may have been turned on in Settings while the app was away
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissions.refresh()
            }
        }
    }
}
