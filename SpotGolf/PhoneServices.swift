import Foundation
import HealthKit
import Observation
import os
import SwiftData
import UIKit

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
    let streamStore: StreamStore
    /// The app's log, with the watch's lines added as they arrive.
    let logFile: LogFile
    let golfBag: GolfBagStore
    let permissions: PermissionChecker
    let pinShare: PinShareCoordinator
    let cloudSync: CloudSync
    /// Putt Data Sharing's consent, profile and sessions.
    let puttSharing: PuttSharingStore
    /// Where rounds and streams are saved. UI tests start each run empty.
    let container: ModelContainer
    /// A round can only start with a paired watch that has the app. UI tests run without one.
    let requiresWatch: Bool

    init(options: LaunchOptions = .current) {
        let isUITesting = options.isUITesting
        requiresWatch = !isUITesting
        SettingsKey.registerDefaults()
        if isUITesting {
            SettingsKey.reset()
        }
        container = Storage.container(for: options)
        let rounds = RoundStore(context: container.mainContext)
        let location = LocationManager()
        let sync = SyncService()
        // Set at launch, since HealthKit may launch the app in the background to hand it the session
        if let mirror = sync.mirror {
            Self.receiveMirroredWorkouts(on: mirror)
        }
        let streams = StreamStore(context: container.mainContext)
        let log = LogFile()
        Log.setSink { log.write($0) }
        // Each line carries the round in progress
        Log.roundID = rounds.currentRound?.id
        rounds.addListener { [weak rounds] _ in Log.roundID = rounds?.currentRound?.id }
        roundStore = rounds
        locationManager = location
        syncService = sync
        streamStore = streams
        logFile = log
        let bag = GolfBagStore(context: container.mainContext)
        golfBag = bag
        courseService = CourseService()

        // Without a watch, rounds start and end on the phone alone
        phoneSync = PhoneSync(sync: sync, rounds: rounds, streams: streams,
                              requiresWatch: !isUITesting) {
            Self.launchWatchApp(sync: sync)
        }
        phoneSync.developerMode = { UserDefaults.standard.bool(forKey: SettingsKey.developerMode) }
        phoneSync.greenZone = { UserDefaults.standard.double(forKey: SettingsKey.greenZone) }

        roundTracker = RoundTracker(rounds: rounds, location: location, showsActivity: !isUITesting)
        // UI tests run without iCloud
        pinShare = PinShareCoordinator(
            rounds: rounds,
            sharing: isUITesting ? NoPinSharing() : CloudKitPinSharing(),
            sharesPins: { UserDefaults.standard.bool(forKey: SettingsKey.sharePins) })
        // UI tests run without iCloud, so their rounds never reach a real account
        cloudSync = CloudSync(rounds: rounds, streams: streams, bag: bag) { state, sync in
            CloudKitSyncEngine(state: state, sync: sync)
        }
        allowsCloudSync = !isUITesting

        // UI tests run without iCloud, so sessions stay on the phone
        let sharing = PuttSharingStore(cloud: isUITesting ? NoPuttSharingCloud() : CloudKitPuttSharing())
        puttSharing = sharing
        sharing.onSettingsChanged = { sync.queue(.phoneSettings($0)) }
        phoneSync.onPuttSession = { sharing.noticeArrived($0) }
        // Files from the watch are chunks of its log or Putt Data Sharing sessions
        let chunks = LogChunkReceiver(file: log)
        sync.fileHandler = { url, metadata in
            if let name = metadata[LogChunk.FileKey.chunk] as? String {
                chunks.receive(url, name: name)
            } else {
                sharing.fileArrived(url, metadata: metadata)
            }
        }
        // Once per launch, as soon as the watch can be told, so a watch that lost them gets them again
        var sentSettings = false
        sync.onReachabilityChange {
            guard !sentSettings, sync.hasCounterpart else { return }
            sentSettings = true
            sync.queue(.phoneSettings(sharing.settingsMessage))
        }
        sharing.uploadNext()
        sharing.sendDeletions()

        // UI tests run on simulators, where permissions are not the point
        permissions = PermissionChecker(
            source: isUITesting ? GrantedPermissionSource() : PhonePermissionSource(),
            required: PhonePermissionSource.required)
        if options.needsAppUpdate {
            cloudSync.showUpdateNotice()
        }
        setCloudSync(UserDefaults.standard.bool(forKey: SettingsKey.iCloudSync))
    }

    /// Off in UI tests.
    private let allowsCloudSync: Bool

    /// The log gzipped into one file, for "Share logs…". Asks the watch for its latest lines
    /// first, without waiting: lines that arrive later go in the next share.
    func gzippedLog() async throws -> URL {
        syncService.queue(.sendLog)
        let file = logFile
        return try await Task.detached { try LogShare.gzip(file) }.value
    }

    /// Starts or stops iCloud sync, for the iCloud Sync setting.
    func setCloudSync(_ enabled: Bool) {
        guard allowsCloudSync else { return }
        if enabled {
            // CloudKit tells the engine about changes from other phones with a silent push
            UIApplication.shared.registerForRemoteNotifications()
        }
        cloudSync.setEnabled(enabled)
    }

    private static let healthStore = HKHealthStore()

    /// Attaches each workout session the watch mirrors to the phone, replacing the last. The
    /// watch ends it, never the phone.
    private static func receiveMirroredWorkouts(on mirror: MirrorTransport) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // HealthKit calls this on its own queue, so it must be @Sendable
        healthStore.workoutSessionMirroringStartHandler = { @Sendable session in
            let box = MirroredSession(session)
            Task { @MainActor in
                Log.workout.notice("Mirrored workout session arrived")
                let channel = WorkoutSessionChannel(session: box.session)
                box.session.delegate = channel
                mirror.attach(channel)
            }
        }
    }

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
            Log.workout.error("Could not launch the watch app: \(reason)")
            Task { @MainActor in
                // Nothing to report when the watch app is already running
                guard !sync.isConnected else { return }
                sync.syncError = String(localized: "Could not open SpotGolf on the watch (\(reason)). Open it on the watch, then tap Retry.")
            }
        }
    }
}

// A session from HealthKit's queue, only used on the main actor
private struct MirroredSession: @unchecked Sendable {
    let session: HKWorkoutSession
    init(_ session: HKWorkoutSession) { self.session = session }
}
