import CloudKit
import Foundation
import Observation

/// A change for the engine to send: a record to save or delete.
enum CloudSyncChange: Hashable, Sendable {
    case save(CKRecord.ID)
    case delete(CKRecord.ID)
}

/// What `CloudSync` needs from `CKSyncEngine`, so tests can run it without iCloud.
@MainActor
protocol CloudSyncEngine: AnyObject, Sendable {
    /// Adds changes to send. The engine asks `CloudSync.record(for:)` for each save as it sends.
    func add(_ changes: [CloudSyncChange])
    /// Makes the `Rounds` zone in iCloud, before any record is saved.
    func addZone()
    /// Fetches changes made on other devices. Throws when the fetch fails, such as with no
    /// iCloud account or no network.
    func fetchChanges() async throws
}

/// Saves ended rounds and the synced settings to the player's private iCloud database with
/// `CKSyncEngine`, and keeps them the same on every phone on the account: the newer change
/// wins. Rounds in progress stay on the phone. See plans/2026-10-22-cloudkit-sync.md.
@MainActor
@Observable
final class CloudSync {
    nonisolated static let containerID = CloudKitPinSharing.containerID
    nonisolated static let zoneID = CKRecordZone.ID(zoneName: "Rounds")
    nonisolated static let roundType = "Round"
    nonisolated static let settingsType = "Settings"
    nonisolated static let settingsRecordID = CKRecord.ID(recordName: "settings", zoneID: zoneID)
    /// The `formatVersion` this build writes on each record type. Bump it for any change to a
    /// record's fields, or to what the round record's asset holds.
    nonisolated static let roundVersion = 1
    nonisolated static let settingsVersion = 1

    /// A record in iCloud was saved by a newer version of the app. Shows the update notice.
    private(set) var needsAppUpdate = false
    /// The update notice's alert was shown this launch. It shows once per launch.
    var hasShownUpdateNotice = false

    /// Whether the engine runs: iCloud Sync is on, outside UI tests.
    var isRunning: Bool { engine != nil }

    @ObservationIgnored private let rounds: RoundStore
    @ObservationIgnored private let streams: StreamStore
    @ObservationIgnored private let logs: LogStore
    @ObservationIgnored private let bag: GolfBagStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let stateURL: URL
    @ObservationIgnored private let scanDelay: Duration
    @ObservationIgnored private let makeEngine: (Data?, CloudSync) -> CloudSyncEngine
    @ObservationIgnored private var engine: CloudSyncEngine?
    @ObservationIgnored private var state: SavedState
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// The latest fetch this phone asked for. Tests wait on it.
    @ObservationIgnored private(set) var fetchTask: Task<Void, Never>?
    /// What each round was when its record was built, until the save is confirmed.
    @ObservationIgnored private var inFlight: [UUID: Signature] = [:]
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    /// `makeEngine` gets the engine's saved state, nil for a fresh start.
    init(rounds: RoundStore, streams: StreamStore, logs: LogStore, bag: GolfBagStore,
         defaults: UserDefaults = .standard,
         stateURL: URL = URL.applicationSupportDirectory.appending(path: "cloud-sync-state.json"),
         scanDelay: Duration = .seconds(2),
         makeEngine: @escaping (Data?, CloudSync) -> CloudSyncEngine) {
        self.rounds = rounds
        self.streams = streams
        self.logs = logs
        self.bag = bag
        self.defaults = defaults
        self.stateURL = stateURL
        self.scanDelay = scanDelay
        self.makeEngine = makeEngine
        state = Self.load(from: stateURL)
        needsAppUpdate = state.blocksAppUpdate
        rounds.addListener { [weak self] event in
            if case .roundsChanged = event {
                self?.scheduleScan()
            }
        }
        // The phone's settings before sync are not a change: iCloud's win on a new phone
        if state.knownSettings == nil {
            state.knownSettings = SyncedSettings(defaults: defaults, bag: bag)
        }
        // Changes are timed even while sync is off, so they win when it is turned on again
        bag.onChange = { [weak self] in self?.settingsMayHaveChanged() }
        observeDefaults()
    }

    // MARK: - Turning on and off

    /// Starts or stops syncing, for the iCloud Sync setting. Stopping keeps everything on the
    /// phone and in iCloud. Starting again fetches everything, so a round deleted while sync
    /// was off comes back, as the setting's footer says.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard engine == nil else { return }
            Log.iCloud.notice("iCloud sync on")
            if !state.hasFetchedOnce || state.blocksRefetch {
                startFresh()
            } else {
                engine = makeEngine(state.engineState, self)
                fetch()
            }
        } else {
            guard engine != nil else { return }
            Log.iCloud.notice("iCloud sync off")
            engine = nil
            scanTask?.cancel()
            inFlight = [:]
            // The next start fetches everything again
            state.hasFetchedOnce = false
            save()
        }
    }

    /// Fetches changes made on other phones, when the app comes back to the front. A first
    /// fetch that failed is tried again.
    func appBecameActive() {
        fetch()
    }

    /// Fetches, and finishes the first fetch after a fresh start when it succeeds. Only a fetch
    /// asked for here counts: the engine reports a fetch that failed as finished too, and a
    /// phone that has not read iCloud must not upload, or a new phone's default settings would
    /// replace the account's.
    private func fetch() {
        guard let engine else { return }
        fetchTask = Task { [weak self] in
            do {
                // Detached, so the call is not part of an engine event this may be called from: a
                // task made inside the engine's delegate callback carries the callback's task-local
                // values, and CloudKit traps an await into the engine from one ("BUG IN CLIENT OF
                // CLOUDKIT: Cannot await a call into CKSyncEngine from within a delegate callback")
                try await Task.detached { try await engine.fetchChanges() }.value
                guard let self, engine === self.engine else { return }
                if !state.hasFetchedOnce {
                    firstFetchSucceeded()
                }
            } catch {
                Log.iCloud.error("Could not fetch from iCloud: \(String(describing: error))")
            }
        }
    }

    /// For UI tests, which run without iCloud.
    func showUpdateNotice() {
        needsAppUpdate = true
    }

    /// Forgets what was synced and fetches everything, as on a phone that never synced.
    private func startFresh() {
        state.engineState = nil
        state.hasFetchedOnce = false
        state.synced = [:]
        state.systemFields = [:]
        state.settingsInICloud = false
        state.blocked = [:]
        inFlight = [:]
        save()
        engine = makeEngine(nil, self)
        engine?.addZone()
        fetch()
    }

    // MARK: - Engine events

    func engineStateChanged(_ data: Data?) {
        state.engineState = data
        save()
    }

    /// Signing in to another account, or out, starts over. Local rounds stay on the phone and
    /// upload under the account signed in to next.
    func accountChanged(signedIn: Bool) {
        guard engine != nil else { return }
        // The engine reports the account it starts with as a sign-in too, and a sign-in
        // before the first fetch succeeded is when it can
        if signedIn, !state.hasFetchedOnce {
            fetch()
            return
        }
        Log.iCloud.notice("iCloud account changed, signed in: \(signedIn)")
        startFresh()
    }

    /// The zone is gone, such as when the player deleted SpotGolf's data in iCloud settings.
    /// Sync turns off rather than putting it all back.
    func zoneDeleted() {
        guard engine != nil else { return }
        Log.iCloud.notice("The iCloud zone was deleted, turning iCloud sync off")
        defaults.set(false, forKey: SettingsKey.iCloudSync)
        setEnabled(false)
    }

    /// Any fetch the engine finished, including its own and ones that failed.
    func fetchFinished() {
        guard engine != nil else { return }
        scan()
    }

    private func firstFetchSucceeded() {
        state.hasFetchedOnce = true
        Log.iCloud.notice("First fetch done: \(state.synced.count) rounds in iCloud")
        // A new account gets this phone's settings; an existing record has already won
        if !state.settingsInICloud, state.blocked[Self.settingsRecordID.recordName] == nil {
            if defaults.object(forKey: SettingsKey.settingsChangedAt) == nil {
                defaults.set(Date(), forKey: SettingsKey.settingsChangedAt)
            }
            engine?.add([.save(Self.settingsRecordID)])
        }
        save()
        scan()
    }

    func fetched(modifications: [CKRecord], deletions: [(id: CKRecord.ID, type: String)]) {
        guard engine != nil else { return }
        for record in modifications {
            switch record.recordType {
            case Self.roundType: fetchedRound(record)
            case Self.settingsType: fetchedSettings(record)
            default: break
            }
        }
        for deletion in deletions {
            switch deletion.type {
            case Self.roundType: deletedRound(deletion.id)
            case Self.settingsType: state.settingsInICloud = false
            default: break
            }
        }
        save()
    }

    func sent(saved: [CKRecord], failed: [(record: CKRecord, error: CKError)], deleted: [CKRecord.ID]) {
        guard engine != nil else { return }
        for record in saved {
            state.systemFields[record.recordID.recordName] = Self.systemFields(of: record)
            if record.recordID == Self.settingsRecordID {
                state.settingsInICloud = true
            } else if let id = UUID(uuidString: record.recordID.recordName), let signature = inFlight.removeValue(forKey: id) {
                state.synced[id] = signature
            }
            Self.removeAssetFile(for: record.recordID)
        }
        for (record, error) in failed {
            failedSave(record, error)
        }
        for id in deleted {
            state.systemFields.removeValue(forKey: id.recordName)
            if let roundID = UUID(uuidString: id.recordName) {
                state.synced.removeValue(forKey: roundID)
            }
        }
        save()
        // A round changed while its record was on the way is saved again
        scheduleScan()
    }

    /// The record to save for a pending change, or nil to drop it.
    func record(for id: CKRecord.ID) -> CKRecord? {
        guard engine != nil, state.blocked[id.recordName] == nil else { return nil }
        if id == Self.settingsRecordID {
            return settingsRecord()
        }
        guard let roundID = UUID(uuidString: id.recordName), let round = rounds.round(roundID),
              round.status == .ended else { return nil }
        let records = streams.data(for: roundID, from: 0, maxBytes: Int.max)
        let url = Self.assetFile(for: id)
        do {
            try RoundArchive(round: round, records: records).gzipped().write(to: url, options: .atomic)
        } catch {
            Log.iCloud.error("Could not pack round \(roundID) for iCloud: \(String(describing: error))")
            return nil
        }
        let record = baseRecord(type: Self.roundType, id: id)
        record["formatVersion"] = Self.roundVersion
        record["changedAt"] = round.changedAt
        record["archive"] = CKAsset(fileURL: url)
        inFlight[roundID] = Signature(round, records: streams.count(for: roundID))
        return record
    }

    // MARK: - Rounds

    /// Marks every ended round that differs from its iCloud copy, and every synced round no
    /// longer on the phone. Waits for the first fetch, so iCloud's copies are known first.
    func scan() {
        guard let engine, state.hasFetchedOnce else { return }
        var changes: [CloudSyncChange] = []
        for round in rounds.rounds where round.status == .ended {
            let id = Self.recordID(for: round.id)
            guard state.blocked[id.recordName] == nil,
                  state.synced[round.id] != Signature(round, records: streams.count(for: round.id)) else { continue }
            changes.append(.save(id))
        }
        for id in state.synced.keys where rounds.round(id) == nil {
            changes.append(.delete(Self.recordID(for: id)))
        }
        if !changes.isEmpty {
            engine.add(changes)
        }
    }

    private func scheduleScan() {
        guard engine != nil else { return }
        scanTask?.cancel()
        scanTask = Task { [weak self, scanDelay] in
            try? await Task.sleep(for: scanDelay)
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    private func fetchedRound(_ record: CKRecord) {
        let name = record.recordID.recordName
        guard let id = UUID(uuidString: name) else { return }
        state.systemFields[name] = Self.systemFields(of: record)
        let version = record["formatVersion"] as? Int ?? 0
        guard version <= Self.roundVersion else {
            block(name, version: version)
            return
        }
        let remoteChangedAt = record["changedAt"] as? Date ?? .distantPast
        guard let local = rounds.round(id) else {
            // Deleted here, with the delete not sent yet: the delete wins
            guard state.synced[id] == nil else { return }
            download(record, id: id)
            return
        }
        guard !local.isInProgress else { return }
        if Self.isNewer(remoteChangedAt, than: local.changedAt) {
            download(record, id: id)
        } else if Self.isNewer(local.changedAt, than: remoteChangedAt) {
            // Saved again by the next scan
            state.synced.removeValue(forKey: id)
        } else {
            state.synced[id] = Signature(local, records: streams.count(for: id))
        }
    }

    private func download(_ record: CKRecord, id: UUID) {
        guard let url = (record["archive"] as? CKAsset)?.fileURL else {
            Log.iCloud.error("Round \(id) in iCloud has no archive")
            return
        }
        let archive: RoundArchive
        let records: Data
        do {
            archive = try RoundArchive.read(gzipped: Data(contentsOf: url))
            records = try archive.records()
        } catch RoundArchive.ArchiveError.newerVersion, StreamEncoding.DecodeError.newerVersion {
            // A newer archive in a record of a known version still needs the newer app
            block(record.recordID.recordName, version: Self.roundVersion + 1)
            return
        } catch {
            Log.iCloud.error("Could not read round \(id) from iCloud: \(String(describing: error))")
            return
        }
        // Marked synced first, so the change it makes is not sent back
        state.synced[id] = Signature(changedAt: archive.changedAt, records: records.count / StreamRecord.size)
        if rounds.round(id) == nil {
            rounds.add(archive.makeRound())
        } else {
            rounds.replace(id) { archive.apply(to: $0) }
        }
        streams.replace(id, with: records)
        Log.iCloud.notice("Downloaded round \(id) from iCloud")
    }

    private func deletedRound(_ recordID: CKRecord.ID) {
        state.systemFields.removeValue(forKey: recordID.recordName)
        state.blocked.removeValue(forKey: recordID.recordName)
        guard let id = UUID(uuidString: recordID.recordName) else { return }
        state.synced.removeValue(forKey: id)
        guard let round = rounds.round(id), round.status == .ended else { return }
        rounds.deleteRound(id)
        streams.delete(id)
        logs.delete(id)
        Log.iCloud.notice("Deleted round \(id), deleted in iCloud")
    }

    private func failedSave(_ record: CKRecord, _ error: CKError) {
        let id = record.recordID
        if let roundID = UUID(uuidString: id.recordName) {
            inFlight.removeValue(forKey: roundID)
        }
        Self.removeAssetFile(for: id)
        switch error.code {
        case .serverRecordChanged:
            // Saved again when this phone's copy is newer; fetched when iCloud's is
            guard let server = error.serverRecord else { return }
            state.systemFields[id.recordName] = Self.systemFields(of: server)
            let version = server["formatVersion"] as? Int ?? 0
            let current = id == Self.settingsRecordID ? Self.settingsVersion : Self.roundVersion
            guard version <= current else {
                block(id.recordName, version: version)
                return
            }
            let serverChangedAt = server["changedAt"] as? Date ?? .distantPast
            if Self.isNewer(serverChangedAt, than: localChangedAt(of: id)) {
                fetch()
            } else {
                engine?.add([.save(id)])
            }
        case .zoneNotFound, .userDeletedZone:
            engine?.addZone()
            engine?.add([.save(id)])
        case .unknownItem:
            state.systemFields.removeValue(forKey: id.recordName)
            engine?.add([.save(id)])
        default:
            Log.iCloud.error("Could not save \(id.recordName) to iCloud: \(String(describing: error))")
        }
    }

    private func localChangedAt(of id: CKRecord.ID) -> Date {
        if id == Self.settingsRecordID {
            return defaults.object(forKey: SettingsKey.settingsChangedAt) as? Date ?? .distantPast
        }
        return UUID(uuidString: id.recordName).flatMap { rounds.round($0)?.changedAt } ?? .distantPast
    }

    /// A record saved by a newer version of the app: left alone, and never saved over.
    private func block(_ recordName: String, version: Int) {
        Log.iCloud.notice("\(recordName) in iCloud has format \(version), newer than this app reads")
        state.blocked[recordName] = version
        needsAppUpdate = true
    }

    // MARK: - Settings

    private func fetchedSettings(_ record: CKRecord) {
        state.systemFields[record.recordID.recordName] = Self.systemFields(of: record)
        state.settingsInICloud = true
        let version = record["formatVersion"] as? Int ?? 0
        guard version <= Self.settingsVersion else {
            block(record.recordID.recordName, version: version)
            return
        }
        state.blocked.removeValue(forKey: record.recordID.recordName)
        let remoteChangedAt = record["changedAt"] as? Date ?? .distantPast
        let local = defaults.object(forKey: SettingsKey.settingsChangedAt) as? Date
        if local.map({ Self.isNewer(remoteChangedAt, than: $0) }) ?? true {
            guard let settings = Self.settings(from: record) else {
                Log.iCloud.error("Could not read the settings from iCloud")
                return
            }
            // Known first, so the change it makes is not sent back
            state.knownSettings = settings
            settings.apply(defaults: defaults, bag: bag)
            defaults.set(remoteChangedAt, forKey: SettingsKey.settingsChangedAt)
            Log.iCloud.notice("Downloaded the settings from iCloud")
        } else if let local, Self.isNewer(local, than: remoteChangedAt) {
            engine?.add([.save(Self.settingsRecordID)])
        }
    }

    /// Marks the settings changed when the synced ones differ from what was last seen.
    private func settingsMayHaveChanged() {
        let current = SyncedSettings(defaults: defaults, bag: bag)
        guard current != state.knownSettings else { return }
        state.knownSettings = current
        defaults.set(Date(), forKey: SettingsKey.settingsChangedAt)
        save()
        if let engine, state.hasFetchedOnce, state.blocked[Self.settingsRecordID.recordName] == nil {
            engine.add([.save(Self.settingsRecordID)])
        }
    }

    private func observeDefaults() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: nil) { [weak self] _ in
            // Posted on the thread that changed the setting: the app's own changes come on the main thread
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.settingsMayHaveChanged()
                }
            } else {
                Task { @MainActor in
                    self?.settingsMayHaveChanged()
                }
            }
        }
    }

    private func settingsRecord() -> CKRecord {
        let settings = SyncedSettings(defaults: defaults, bag: bag)
        let record = baseRecord(type: Self.settingsType, id: Self.settingsRecordID)
        record["formatVersion"] = Self.settingsVersion
        record["changedAt"] = defaults.object(forKey: SettingsKey.settingsChangedAt) as? Date ?? Date()
        record["stationaryThreshold"] = settings.stationaryThreshold
        record["greenZone"] = settings.greenZone
        record["sharePins"] = settings.sharePins ? 1 : 0
        record["clubs"] = try? JSONEncoder().encode(settings.clubs)
        return record
    }

    nonisolated static func settings(from record: CKRecord) -> SyncedSettings? {
        guard let stationaryThreshold = record["stationaryThreshold"] as? Double,
              let greenZone = record["greenZone"] as? Double,
              let sharePins = record["sharePins"] as? Int,
              let clubsData = record["clubs"] as? Data,
              let clubs = try? JSONDecoder().decode([SyncedSettings.Club].self, from: clubsData) else { return nil }
        return SyncedSettings(stationaryThreshold: stationaryThreshold, greenZone: greenZone,
                              sharePins: sharePins != 0, clubs: clubs)
    }

    // MARK: - Records

    nonisolated static func recordID(for roundID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: roundID.uuidString, zoneID: zoneID)
    }

    /// The record as iCloud last returned it, so a save is not taken for a conflict, or a new one.
    private func baseRecord(type: String, id: CKRecord.ID) -> CKRecord {
        if let data = state.systemFields[id.recordName], let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            let record = CKRecord(coder: coder)
            coder.finishDecoding()
            if let record, record.recordType == type {
                return record
            }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    private nonisolated static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// CloudKit keeps dates to the millisecond, so closer than that is the same change.
    nonisolated static func isNewer(_ date: Date, than other: Date) -> Bool {
        date.timeIntervalSince(other) > 0.001
    }

    private nonisolated static func assetFile(for id: CKRecord.ID) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(id.recordName).roundarchive")
    }

    private nonisolated static func removeAssetFile(for id: CKRecord.ID) {
        try? FileManager.default.removeItem(at: assetFile(for: id))
    }

    // MARK: - Saved state

    /// What a round was when it was last synced: a change to either is a new save.
    struct Signature: Codable, Equatable {
        var changedAt: Date
        var records: Int

        init(changedAt: Date, records: Int) {
            self.changedAt = changedAt
            self.records = records
        }

        init(_ round: Round, records: Int) {
            self.init(changedAt: round.changedAt, records: records)
        }

        static func == (lhs: Signature, rhs: Signature) -> Bool {
            lhs.records == rhs.records && !CloudSync.isNewer(lhs.changedAt, than: rhs.changedAt)
                && !CloudSync.isNewer(rhs.changedAt, than: lhs.changedAt)
        }
    }

    struct SavedState: Codable {
        /// `CKSyncEngine`'s own state, as the engine encodes it.
        var engineState: Data?
        /// Set once the first fetch after a fresh start finishes.
        var hasFetchedOnce = false
        /// Each round as last saved to or downloaded from iCloud.
        var synced: [UUID: Signature] = [:]
        /// Each record's system fields as iCloud last returned them, by record name.
        var systemFields: [String: Data] = [:]
        /// The synced settings as last seen on this phone.
        var knownSettings: SyncedSettings?
        var settingsInICloud = false
        /// Records saved by a newer app version, by record name, with their version.
        var blocked: [String: Int] = [:]

        /// A blocked record this build can't read.
        var blocksAppUpdate: Bool {
            blocked.contains { name, version in
                version > (name == CloudSync.settingsRecordID.recordName ? CloudSync.settingsVersion : CloudSync.roundVersion)
            }
        }

        /// The app was updated since a record was blocked: fetch everything to read it.
        var blocksRefetch: Bool {
            !blocked.isEmpty && !blocksAppUpdate
        }
    }

    private static func load(from url: URL) -> SavedState {
        guard let data = try? Data(contentsOf: url) else { return SavedState() }
        do {
            return try JSONDecoder().decode(SavedState.self, from: data)
        } catch {
            Log.iCloud.error("Could not read the iCloud sync state, starting over: \(String(describing: error))")
            return SavedState()
        }
    }

    private func save() {
        do {
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        } catch {
            Log.iCloud.error("Could not save the iCloud sync state: \(String(describing: error))")
        }
    }
}
