import SwiftUI
import os
import HealthKit

@main
struct SpotGolfApp: App {
    @State private var roundStore: RoundStore
    @State private var locationManager: LocationManager
    @State private var roundTracker: RoundTracker
    @State private var syncService: SyncService
    @State private var phoneSync: PhoneSync
    @State private var courseService = CourseService()
    @State private var suggestionStore: SuggestionStore
    @State private var settingsStore: SettingsStore
    @State private var streamStore: StreamStore
    @State private var permissions: PermissionChecker
    @State private var pinShare: PinShareCoordinator
    @State private var puttCaptures: PuttCaptureStore

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
        let settings = SettingsStore()
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
        let puttCaptures = PuttCaptureStore()
        (sync.transport as? WatchConnectivityTransport)?.onFileReceived = { url, metadata in
            puttCaptures.receive(file: url, metadata: metadata)
        }
        _puttCaptures = State(initialValue: puttCaptures)
        _roundStore = State(initialValue: rounds)
        _locationManager = State(initialValue: location)
        _roundTracker = State(initialValue: RoundTracker(rounds: rounds, location: location,
                                                         showsActivity: !isUITesting))
        _syncService = State(initialValue: sync)
        _streamStore = State(initialValue: streams)
        _suggestionStore = State(initialValue: suggestions)
        _phoneSync = State(initialValue: phoneSync)
        _settingsStore = State(initialValue: settings)
        // UI tests run without iCloud
        _pinShare = State(initialValue: PinShareCoordinator(
            rounds: rounds,
            sharing: isUITesting ? NoPinSharing() : CloudKitPinSharing(),
            sharesPins: { settings.settings.sharePins }))
        // UI tests run on simulators, where permissions are not the point
        _permissions = State(initialValue: PermissionChecker(
            source: isUITesting ? GrantedPermissionSource() : PhonePermissionSource(),
            required: PhonePermissionSource.required))
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(permissions)
                .environment(roundStore)
                .environment(locationManager)
                .environment(roundTracker)
                .environment(syncService)
                .environment(phoneSync)
                .environment(courseService)
                .environment(suggestionStore)
                .environment(settingsStore)
                .environment(streamStore)
                .environment(puttCaptures)
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
    @Environment(PermissionChecker.self) private var permissions
    @Environment(RoundTracker.self) private var roundTracker
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if permissions.allGranted {
                ContentView()
            } else {
                PhonePermissionsView()
            }
        }
        // Permissions may have changed in Settings, or an "Allow Once" grant ran out. A Live
        // Activity that could not start in the background starts now.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissions.refresh()
                roundTracker.appBecameActive()
            }
        }
    }
}
