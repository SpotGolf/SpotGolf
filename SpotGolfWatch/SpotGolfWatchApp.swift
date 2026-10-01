import SwiftUI

@main
struct SpotGolfWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(appDelegate.roundStore)
                .environmentObject(appDelegate.locationManager)
                .environmentObject(appDelegate.syncService)
                .environmentObject(appDelegate.watchSync)
                .environmentObject(appDelegate.workoutManager)
                .environmentObject(appDelegate.holeAdvance)
                .environmentObject(appDelegate.permissions)
        }
    }
}

/// The permissions screen until every permission is granted, then the round screen. A round
/// already recording stays on screen, so it can still be ended.
private struct WatchRootView: View {
    @EnvironmentObject var permissions: PermissionChecker
    @EnvironmentObject var roundStore: RoundStore
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
