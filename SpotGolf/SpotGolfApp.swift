import SwiftUI
import os

@main
struct SpotGolfApp: App {
    @State private var services: PhoneServices

    init() {
        Log.rounds.notice("Phone app launched")
        _services = State(initialValue: PhoneServices())
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(services)
                .onAppear {
                    Task {
                        await services.courseService.refreshIndex()
                    }
                }
        }
    }
}

/// The permissions screen until every required permission is granted, then the app.
private struct PhoneRootView: View {
    @Environment(PhoneServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if services.permissions.allGranted {
                ContentView()
            } else {
                PhonePermissionsView()
            }
        }
        // Permissions may have changed in Settings, or an "Allow Once" grant ran out. A Live
        // Activity that could not start in the background starts now.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                services.permissions.refresh()
                services.roundTracker.appBecameActive()
            }
        }
    }
}
