import SwiftData
import SwiftUI
import UIKit
import os

@main
struct SpotGolfApp: App {
    @State private var services: PhoneServices
    /// The splash shows once, over the app, on a cold launch
    @State private var showsSplash = SplashTimeline.shows(isUITesting: LaunchOptions.current.isUITesting,
                                                          reducesMotion: UIAccessibility.isReduceMotionEnabled)

    init() {
        Log.rounds.notice("Phone app launched")
        // UI tests run at machine speed: nothing waits for an animation to finish
        if LaunchOptions.current.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        _services = State(initialValue: PhoneServices())
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                PhoneRootView()
                    .transaction { transaction in
                        if LaunchOptions.current.isUITesting {
                            transaction.disablesAnimations = true
                        }
                    }
                    .environment(services)
                    .modelContainer(services.container)
                    .onAppear {
                        Task {
                            await services.courseService.refreshIndex()
                        }
                    }
                if showsSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showsSplash = false
                        }
                    }
                    .transition(.opacity)
                    // Stays on top while it fades out
                    .zIndex(1)
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
                services.cloudSync.appBecameActive()
            }
        }
    }
}
