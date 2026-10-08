import SwiftData
import SwiftUI

@main
struct SpotGolfWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(appDelegate.services)
                .modelContainer(appDelegate.services.container)
        }
    }
}

/// The permissions screen until every permission is granted, then the round screen. A round
/// already recording stays on screen, so it can still be ended.
private struct WatchRootView: View {
    @Environment(WatchServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if services.permissions.allGranted || services.roundStore.activeRound != nil {
                WatchRoundView()
            } else {
                PermissionsView()
            }
        }
        // Permissions may have been turned on in Settings while the app was away
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                services.permissions.refresh()
            }
        }
    }
}
