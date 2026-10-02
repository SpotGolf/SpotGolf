import SwiftUI
import os
import HealthKit

@main
struct SpotGolfApp: App {
    @StateObject private var roundStore: RoundStore
    @StateObject private var locationManager: LocationManager
    @StateObject private var roundTracker: RoundTracker
    @StateObject private var syncService: SyncService
    @StateObject private var phoneSync: PhoneSync
    @StateObject private var courseService = CourseService()
    @StateObject private var suggestionStore: SuggestionStore
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var streamStore: StreamStore
    @StateObject private var permissions: PermissionChecker

    init() {
        Log.rounds.notice("Phone app launched")
        let isUITesting = CommandLine.arguments.contains("--ui-testing")
        let rounds = RoundStore()
        if isUITesting {
            rounds.rounds = []
        }
        let location = LocationManager()
        let sync = SyncService()
        let streams = StreamStore()
        let suggestions = SuggestionStore()
        let healthStore = HKHealthStore()
        // UI tests run without a paired watch, so rounds start and end on the phone alone
        let phoneSync = PhoneSync(sync: sync, rounds: rounds, streams: streams, suggestions: suggestions,
                                  requiresWatch: !isUITesting) {
            guard HKHealthStore.isHealthDataAvailable() else { return }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .golf
            configuration.locationType = .outdoor
            // Needs permission to save workouts, which the app has before it opens
            healthStore.startWatchApp(with: configuration) { success, error in
                guard !success else { return }
                let reason = error?.localizedDescription ?? "unknown error"
                Log.workout.error("Could not launch the watch app: \(reason, privacy: .public)")
                Task { @MainActor in
                    // Nothing to report when the watch app is already running
                    guard !sync.isConnected else { return }
                    sync.syncError = "Could not open SpotGolf on the watch (\(reason)). Open it on the watch, then tap Retry."
                }
            }
        }
        _roundStore = StateObject(wrappedValue: rounds)
        _locationManager = StateObject(wrappedValue: location)
        _roundTracker = StateObject(wrappedValue: RoundTracker(rounds: rounds, location: location,
                                                               showsActivity: !isUITesting))
        _syncService = StateObject(wrappedValue: sync)
        _streamStore = StateObject(wrappedValue: streams)
        _suggestionStore = StateObject(wrappedValue: suggestions)
        _phoneSync = StateObject(wrappedValue: phoneSync)
        // UI tests run on simulators, where permissions are not the point
        _permissions = StateObject(wrappedValue: PermissionChecker(
            source: isUITesting ? GrantedPermissionSource() : PhonePermissionSource(),
            required: PhonePermissionSource.required))
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(permissions)
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .environmentObject(roundTracker)
                .environmentObject(syncService)
                .environmentObject(phoneSync)
                .environmentObject(courseService)
                .environmentObject(suggestionStore)
                .environmentObject(settingsStore)
                .environmentObject(streamStore)
                .onAppear {
                    Task {
                        await courseService.refreshIndex()
                    }
                }
        }
    }
}

/// The permissions screen until every required permission is granted, then the app.
private struct PhoneRootView: View {
    @EnvironmentObject var permissions: PermissionChecker
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if permissions.allGranted {
                ContentView()
            } else {
                PhonePermissionsView()
            }
        }
        // Permissions may have changed in Settings, or an "Allow Once" grant ran out
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissions.refresh()
            }
        }
    }
}
