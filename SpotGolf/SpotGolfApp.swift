import SwiftUI
import HealthKit

@main
struct SpotGolfApp: App {
    @StateObject private var roundStore: RoundStore
    @StateObject private var locationManager = LocationManager()
    @StateObject private var syncService: SyncService
    @StateObject private var phoneSync: PhoneSync
    @StateObject private var courseService = CourseService()
    @StateObject private var guessStore: GuessStore
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var streamStore: StreamStore

    init() {
        let isUITesting = CommandLine.arguments.contains("--ui-testing")
        let rounds = RoundStore()
        if isUITesting {
            rounds.rounds = []
        }
        let sync = SyncService()
        let streams = StreamStore()
        let guesses = GuessStore()
        let healthStore = HKHealthStore()
        // UI tests run without a paired watch, so rounds start and end on the phone alone
        let phoneSync = PhoneSync(sync: sync, rounds: rounds, streams: streams, guesses: guesses,
                                  requiresWatch: !isUITesting) {
            guard HKHealthStore.isHealthDataAvailable() else { return }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .golf
            configuration.locationType = .outdoor
            // Launching the watch app for a workout needs permission to save workouts. The
            // prompt shows only the first time.
            healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { _, _ in
                healthStore.startWatchApp(with: configuration) { success, error in
                    guard !success else { return }
                    let reason = error?.localizedDescription ?? "unknown error"
                    print("Could not launch the watch app: \(reason)")
                    Task { @MainActor in
                        // Nothing to report when the watch app is already running
                        guard !sync.isConnected else { return }
                        sync.syncError = "Could not open SpotGolf on the watch (\(reason)). Open it on the watch, then tap Retry."
                    }
                }
            }
        }
        _roundStore = StateObject(wrappedValue: rounds)
        _syncService = StateObject(wrappedValue: sync)
        _streamStore = StateObject(wrappedValue: streams)
        _guessStore = StateObject(wrappedValue: guesses)
        _phoneSync = StateObject(wrappedValue: phoneSync)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .environmentObject(syncService)
                .environmentObject(phoneSync)
                .environmentObject(courseService)
                .environmentObject(guessStore)
                .environmentObject(settingsStore)
                .environmentObject(streamStore)
                .onAppear {
                    locationManager.requestPermission()
                    Task {
                        await courseService.refreshIndex()
                    }
                }
        }
    }
}
