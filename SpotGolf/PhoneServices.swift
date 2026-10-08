import Foundation
import HealthKit
import Observation
import os

/// Every service the phone app runs, built and wired together once at launch. Views read it
/// from the environment and use the services they need.
@Observable
@MainActor
final class PhoneServices {
    let roundStore: RoundStore
    let locationManager: LocationManager
    let roundTracker: RoundTracker
    let syncService: SyncService
    let phoneSync: PhoneSync
    let courseService: CourseService
    let suggestionStore: SuggestionStore
    let settingsStore: SettingsStore
    let streamStore: StreamStore
    let permissions: PermissionChecker
    let pinShare: PinShareCoordinator
    let puttCaptures: PuttCaptureStore
    /// A round can only start with a paired watch that has the app. UI tests run without one.
    let requiresWatch: Bool

    init(options: LaunchOptions = .current) {
        let isUITesting = options.isUITesting
        requiresWatch = !isUITesting
        let rounds = RoundStore()
        if isUITesting {
            rounds.rounds = []
        }
        let location = LocationManager()
        let sync = SyncService()
        let streams = StreamStore()
        let suggestions = SuggestionStore()
        let settings = SettingsStore()
        roundStore = rounds
        locationManager = location
        syncService = sync
        streamStore = streams
        suggestionStore = suggestions
        settingsStore = settings
        courseService = CourseService()

        // Without a watch, rounds start and end on the phone alone
        phoneSync = PhoneSync(sync: sync, rounds: rounds, streams: streams, suggestions: suggestions,
                              requiresWatch: !isUITesting) {
            Self.launchWatchApp(sync: sync)
        }

        let puttCaptures = PuttCaptureStore()
        (sync.transport as? WatchConnectivityTransport)?.onFileReceived = { url, metadata in
            puttCaptures.receive(file: url, metadata: metadata)
        }
        self.puttCaptures = puttCaptures

        roundTracker = RoundTracker(rounds: rounds, location: location, showsActivity: !isUITesting)
        // UI tests run without iCloud
        pinShare = PinShareCoordinator(
            rounds: rounds,
            sharing: isUITesting ? NoPinSharing() : CloudKitPinSharing(),
            sharesPins: { settings.settings.sharePins })
        // UI tests run on simulators, where permissions are not the point
        permissions = PermissionChecker(
            source: isUITesting ? GrantedPermissionSource() : PhonePermissionSource(),
            required: PhonePermissionSource.required)
    }

    private static let healthStore = HKHealthStore()

    /// Opens the watch app with a golf workout, so it can record the round.
    private static func launchWatchApp(sync: SyncService) {
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
}
