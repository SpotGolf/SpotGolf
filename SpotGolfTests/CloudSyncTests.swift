import CloudKit
import CoreLocation
import SwiftData
import XCTest
@testable import SpotGolf

/// Records what `CloudSync` asks of the engine, in place of `CKSyncEngine`.
@MainActor
private final class FakeEngine: CloudSyncEngine {
    let startState: Data?
    var saves: [CKRecord.ID] = []
    var deletes: [CKRecord.ID] = []
    var zoneAdds = 0
    var fetches = 0
    /// Fetches fail, as with no iCloud account.
    var failsFetches = false

    init(startState: Data?) {
        self.startState = startState
    }

    func add(_ changes: [CloudSyncChange]) {
        for change in changes {
            switch change {
            case .save(let id): saves.append(id)
            case .delete(let id): deletes.append(id)
            }
        }
    }

    func addZone() { zoneAdds += 1 }
    func fetchChanges() async throws {
        fetches += 1
        if failsFetches {
            throw CKError(.notAuthenticated)
        }
    }
}

@MainActor
final class CloudSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var rounds: RoundStore!
    private var streams: StreamStore!
    private var logs: LogStore!
    private var bag: GolfBagStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var stateURL: URL!
    private var engines: [FakeEngine] = []
    private var sync: CloudSync!

    private var engine: FakeEngine { engines.last! }

    override func setUp() async throws {
        try await super.setUp()
        container = Storage.inMemoryContainer()
        let context = ModelContext(container)
        suiteName = "CloudSyncTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        SettingsKey.registerDefaults(in: defaults)
        rounds = RoundStore(context: context)
        streams = StreamStore(context: context)
        logs = LogStore(context: context)
        bag = GolfBagStore(context: context, defaults: defaults)
        stateURL = FileManager.default.temporaryDirectory.appending(path: "\(suiteName!).json")
        engines = []
        sync = makeSync()
    }

    override func tearDown() async throws {
        sync = nil
        try? FileManager.default.removeItem(at: stateURL)
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        try await super.tearDown()
    }

    private func makeSync() -> CloudSync {
        CloudSync(rounds: rounds, streams: streams, logs: logs, bag: bag, defaults: defaults, stateURL: stateURL,
                  scanDelay: .milliseconds(50)) { [unowned self] state, _ in
            let engine = FakeEngine(startState: state)
            engines.append(engine)
            return engine
        }
    }

    /// Turns sync on and finishes its first fetch with `records` in iCloud.
    private func start(with records: [CKRecord] = []) async {
        sync.setEnabled(true)
        sync.fetched(modifications: records, deletions: [])
        await sync.fetchTask?.value
    }

    @discardableResult
    private func addEndedRound(changedAt: Date = Date(timeIntervalSince1970: 1_760_290_000)) -> Round {
        let round = RoundArchiveTests.endedRound()
        rounds.add(round)
        streams.appendData(RoundArchiveTests.records(count: 100), roundID: round.id)
        rounds.replace(round.id) { $0.changedAt = changedAt }
        return round
    }

    /// A `Round` record as another phone would save it.
    private func roundRecord(_ round: Round, records: Data = RoundArchiveTests.records(count: 100),
                             version: Int = CloudSync.roundVersion) throws -> CKRecord {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).roundarchive")
        try RoundArchive(round: round, records: records).gzipped().write(to: url)
        let record = CKRecord(recordType: CloudSync.roundType, recordID: CloudSync.recordID(for: round.id))
        record["formatVersion"] = version
        record["changedAt"] = round.changedAt
        record["archive"] = CKAsset(fileURL: url)
        return record
    }

    private func settingsRecord(greenZone: Double, clubs: [SyncedSettings.Club], changedAt: Date,
                                version: Int = CloudSync.settingsVersion) throws -> CKRecord {
        let record = CKRecord(recordType: CloudSync.settingsType, recordID: CloudSync.settingsRecordID)
        record["formatVersion"] = version
        record["changedAt"] = changedAt
        record["stationaryThreshold"] = 45.0
        record["greenZone"] = greenZone
        record["sharePins"] = 0
        record["clubs"] = try JSONEncoder().encode(clubs)
        return record
    }

    private func recordID(_ round: Round) -> CKRecord.ID {
        CloudSync.recordID(for: round.id)
    }

    // MARK: - Saving rounds

    func testAnEndedRoundIsSavedAndARoundInProgressIsNot() async throws {
        let ended = addEndedRound()
        let active = rounds.startRound(courseSelection: .test)

        await start()

        XCTAssertTrue(engine.saves.contains(recordID(ended)))
        XCTAssertFalse(engine.saves.contains(recordID(active)))
        let record = try XCTUnwrap(sync.record(for: recordID(ended)))
        XCTAssertEqual(record["formatVersion"] as? Int, CloudSync.roundVersion)
        XCTAssertNil(sync.record(for: recordID(active)))
        let url = try XCTUnwrap((record["archive"] as? CKAsset)?.fileURL)
        let archive = try RoundArchive.read(gzipped: Data(contentsOf: url))
        XCTAssertEqual(archive.holes, ended.holes)
        XCTAssertEqual(try archive.records().count, 100 * StreamRecord.size)
    }

    func testASavedRoundIsNotSavedAgainUntilItChanges() async throws {
        let round = addEndedRound()
        await start()
        let record = try XCTUnwrap(sync.record(for: recordID(round)))
        sync.sent(saved: [record], failed: [], deleted: [])
        engine.saves = []

        sync.scan()
        XCTAssertEqual(engine.saves, [])

        rounds.setShotQuality(.good, strokeID: round.holes[0].strokes[1].id, in: round.id)
        sync.scan()
        XCTAssertEqual(engine.saves, [recordID(round)])
    }

    func testABurstOfEditsIsOneSave() async throws {
        let round = addEndedRound()
        await start()
        sync.sent(saved: [try XCTUnwrap(sync.record(for: recordID(round)))], failed: [], deleted: [])
        engine.saves = []

        for quality in [ShotQuality.okay, .good, .bad] {
            rounds.setShotQuality(quality, strokeID: round.holes[0].strokes[1].id, in: round.id)
        }
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(engine.saves, [recordID(round)])
    }

    func testAStreamChangeIsASave() async throws {
        let round = addEndedRound()
        await start()
        sync.sent(saved: [try XCTUnwrap(sync.record(for: recordID(round)))], failed: [], deleted: [])
        engine.saves = []

        streams.truncate(round.id, to: 50)
        sync.scan()

        XCTAssertEqual(engine.saves, [recordID(round)])
    }

    func testADeletedRoundIsDeletedInICloud() async throws {
        let round = addEndedRound()
        await start()
        sync.sent(saved: [try XCTUnwrap(sync.record(for: recordID(round)))], failed: [], deleted: [])

        rounds.deleteRound(round.id)
        sync.scan()

        XCTAssertEqual(engine.deletes, [recordID(round)])
        sync.sent(saved: [], failed: [], deleted: [recordID(round)])
        engine.deletes = []
        sync.scan()
        XCTAssertEqual(engine.deletes, [])
    }

    // MARK: - Downloads

    func testANewRoundIsDownloaded() async throws {
        let remote = RoundArchiveTests.endedRound()

        await start(with: [try roundRecord(remote)])

        let local = try XCTUnwrap(rounds.round(remote.id))
        XCTAssertEqual(local.holes, remote.holes)
        XCTAssertEqual(local.status, .ended)
        XCTAssertEqual(streams.count(for: remote.id), 100)
        XCTAssertFalse(engine.saves.contains(recordID(remote)), "A downloaded round is not sent back")
    }

    func testANewerCopyReplacesAnOlderRound() async throws {
        let local = addEndedRound(changedAt: Date(timeIntervalSince1970: 1_760_290_000))
        let remote = RoundArchiveTests.endedRound(id: local.id)
        remote.holes[1].strokes = []
        remote.changedAt = Date(timeIntervalSince1970: 1_760_300_000)

        await start(with: [try roundRecord(remote, records: RoundArchiveTests.records(count: 40))])

        XCTAssertEqual(rounds.round(local.id)?.holes[1].strokes, [])
        XCTAssertEqual(rounds.round(local.id)?.changedAt, remote.changedAt)
        XCTAssertEqual(streams.count(for: local.id), 40)
        XCTAssertFalse(engine.saves.contains(recordID(local)))
    }

    func testANewerRoundHereIsKeptAndSaved() async throws {
        let local = addEndedRound(changedAt: Date(timeIntervalSince1970: 1_760_300_000))
        let remote = RoundArchiveTests.endedRound(id: local.id)
        remote.holes = [RoundHole()]
        remote.changedAt = Date(timeIntervalSince1970: 1_760_290_000)

        await start(with: [try roundRecord(remote)])

        XCTAssertEqual(rounds.round(local.id)?.holes.count, 2)
        XCTAssertTrue(engine.saves.contains(recordID(local)))
    }

    func testTheSameRoundIsNotSavedOrDownloaded() async throws {
        let local = addEndedRound()
        let remote = RoundArchiveTests.endedRound(id: local.id)
        remote.changedAt = local.changedAt

        await start(with: [try roundRecord(remote)])

        XCTAssertFalse(engine.saves.contains(recordID(local)))
    }

    func testARoundInProgressIsNotReplaced() async throws {
        let local = rounds.startRound(courseSelection: .test)
        let remote = RoundArchiveTests.endedRound(id: local.id)
        remote.changedAt = Date().addingTimeInterval(3_600)

        await start(with: [try roundRecord(remote)])

        XCTAssertEqual(rounds.round(local.id)?.status, .active)
    }

    func testARoundDeletedInICloudIsDeletedHere() async throws {
        let round = addEndedRound()
        await start()

        sync.fetched(modifications: [], deletions: [(recordID(round), CloudSync.roundType)])

        XCTAssertNil(rounds.round(round.id))
        XCTAssertFalse(streams.hasStream(for: round.id))
    }

    // MARK: - Conflicts

    func testAConflictWithANewerICloudCopyFetchesIt() async throws {
        let round = addEndedRound(changedAt: Date(timeIntervalSince1970: 1_760_290_000))
        await start()
        let record = try XCTUnwrap(sync.record(for: recordID(round)))
        let server = try roundRecord(RoundArchiveTests.endedRound(id: round.id))
        server["changedAt"] = Date(timeIntervalSince1970: 1_760_300_000)
        let fetches = engine.fetches
        engine.saves = []

        sync.sent(saved: [], failed: [(record, CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server]))],
                  deleted: [])
        await sync.fetchTask?.value

        XCTAssertEqual(engine.fetches, fetches + 1)
        XCTAssertEqual(engine.saves, [])
    }

    func testAConflictWithAnOlderICloudCopySavesAgain() async throws {
        let round = addEndedRound(changedAt: Date(timeIntervalSince1970: 1_760_300_000))
        await start()
        let record = try XCTUnwrap(sync.record(for: recordID(round)))
        let server = try roundRecord(RoundArchiveTests.endedRound(id: round.id))
        server["changedAt"] = Date(timeIntervalSince1970: 1_760_290_000)
        engine.saves = []

        sync.sent(saved: [], failed: [(record, CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server]))],
                  deleted: [])

        XCTAssertEqual(engine.saves, [recordID(round)])
    }

    // MARK: - Settings

    func testANewAccountGetsThisPhonesSettings() async throws {
        await start()

        XCTAssertTrue(engine.saves.contains(CloudSync.settingsRecordID))
        let record = try XCTUnwrap(sync.record(for: CloudSync.settingsRecordID))
        XCTAssertEqual(CloudSync.settings(from: record), SyncedSettings(defaults: defaults, bag: bag))
    }

    func testANewPhoneTakesTheSettingsInICloud() async throws {
        let clubs = [SyncedSettings.Club(clubID: "dr", distance: 250), SyncedSettings.Club(clubID: "pt", distance: nil)]

        await start(with: [try settingsRecord(greenZone: 15, clubs: clubs, changedAt: Date(timeIntervalSince1970: 1_000))])

        XCTAssertEqual(defaults.double(forKey: SettingsKey.greenZone), 15)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.stationaryThreshold), 45)
        XCTAssertFalse(defaults.bool(forKey: SettingsKey.sharePins))
        XCTAssertEqual(bag.entries.map(\.clubID), ["dr", "pt"])
        XCTAssertFalse(engine.saves.contains(CloudSync.settingsRecordID), "Downloaded settings are not sent back")
    }

    func testASettingChangeIsSaved() async throws {
        await start(with: [try settingsRecord(greenZone: 15, clubs: [], changedAt: Date(timeIntervalSince1970: 1_000))])
        engine.saves = []

        defaults.set(20.0, forKey: SettingsKey.greenZone)

        XCTAssertEqual(engine.saves, [CloudSync.settingsRecordID])
    }

    func testAClubChangeIsSaved() async throws {
        await start(with: [try settingsRecord(greenZone: 15, clubs: [.init(clubID: "dr", distance: 250)],
                                        changedAt: Date(timeIntervalSince1970: 1_000))])
        engine.saves = []

        bag.setDistance(260, for: try XCTUnwrap(Club.named("dr")))

        XCTAssertEqual(engine.saves, [CloudSync.settingsRecordID])
        XCTAssertEqual(CloudSync.settings(from: try XCTUnwrap(sync.record(for: CloudSync.settingsRecordID)))?.clubs,
                       [.init(clubID: "dr", distance: 260)])
    }

    // MARK: - Versions

    func testANewerRoundFormatIsLeftAloneAndShowsTheNotice() async throws {
        let local = addEndedRound(changedAt: Date(timeIntervalSince1970: 1_760_300_000))
        let remote = RoundArchiveTests.endedRound(id: local.id)
        remote.changedAt = Date(timeIntervalSince1970: 1_760_290_000)

        await start(with: [try roundRecord(remote, version: CloudSync.roundVersion + 1)])

        XCTAssertTrue(sync.needsAppUpdate)
        XCTAssertFalse(engine.saves.contains(recordID(local)), "Never saved over, even when newer here")
        XCTAssertNil(sync.record(for: recordID(local)))
        XCTAssertEqual(rounds.round(local.id)?.holes.count, 2)
    }

    func testANewerSettingsFormatKeepsThisPhonesSettingsAndStopsUploads() async throws {
        let greenZone = defaults.double(forKey: SettingsKey.greenZone)

        await start(with: [try settingsRecord(greenZone: greenZone + 10, clubs: [], changedAt: Date(),
                                        version: CloudSync.settingsVersion + 1)])
        defaults.set(greenZone + 5, forKey: SettingsKey.greenZone)

        XCTAssertTrue(sync.needsAppUpdate)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.greenZone), greenZone + 5)
        XCTAssertFalse(engine.saves.contains(CloudSync.settingsRecordID))
        XCTAssertNil(sync.record(for: CloudSync.settingsRecordID))
    }

    func testTheNoticeStaysUntilTheAppIsUpdated() async throws {
        await start(with: [try roundRecord(RoundArchiveTests.endedRound(), version: CloudSync.roundVersion + 1)])

        sync = makeSync()

        XCTAssertTrue(sync.needsAppUpdate)
    }

    // MARK: - iCloud Sync setting

    func testNothingIsSentWithSyncOff() async throws {
        await start()
        sync.setEnabled(false)
        let engineCount = engines.count

        addEndedRound()
        defaults.set(25.0, forKey: SettingsKey.greenZone)
        sync.scan()

        XCTAssertEqual(engines.count, engineCount)
        XCTAssertNil(sync.record(for: CloudSync.settingsRecordID))
    }

    func testTurningSyncOnAgainFetchesEverythingThenSavesEverything() async throws {
        let round = addEndedRound()
        await start()
        sync.sent(saved: [try XCTUnwrap(sync.record(for: recordID(round)))], failed: [], deleted: [])
        sync.setEnabled(false)
        let deleted = addEndedRound()
        rounds.deleteRound(deleted.id)

        sync.setEnabled(true)

        XCTAssertNil(engine.startState, "A fresh start, so rounds deleted while off come back")
        XCTAssertEqual(engine.saves, [], "Nothing is saved before the fetch")
        await sync.fetchTask?.value
        XCTAssertEqual(engine.fetches, 1)
        XCTAssertTrue(engine.saves.contains(recordID(round)))
        XCTAssertTrue(engine.saves.contains(CloudSync.settingsRecordID))
        XCTAssertEqual(engine.deletes, [])
    }

    func testASettingChangedWhileOffWinsWhenTurnedOnAgain() async throws {
        await start(with: [try settingsRecord(greenZone: 15, clubs: [], changedAt: Date(timeIntervalSince1970: 1_000))])
        sync.setEnabled(false)
        defaults.set(30.0, forKey: SettingsKey.greenZone)

        sync.setEnabled(true)
        sync.fetched(modifications: [try settingsRecord(greenZone: 15, clubs: [], changedAt: Date(timeIntervalSince1970: 1_000))],
                     deletions: [])
        await sync.fetchTask?.value

        XCTAssertEqual(defaults.double(forKey: SettingsKey.greenZone), 30)
        XCTAssertTrue(engine.saves.contains(CloudSync.settingsRecordID))
    }

    // MARK: - First fetch

    func testNothingIsSentUntilTheFirstFetchSucceeds() async throws {
        let round = addEndedRound()
        sync.setEnabled(true)
        engine.failsFetches = true
        await sync.fetchTask?.value

        sync.fetchFinished()
        sync.scan()
        XCTAssertEqual(engine.saves, [], "A failed fetch is not a first fetch: a new phone would upload its default settings")

        engine.failsFetches = false
        sync.appBecameActive()
        await sync.fetchTask?.value

        XCTAssertTrue(engine.saves.contains(recordID(round)))
        XCTAssertTrue(engine.saves.contains(CloudSync.settingsRecordID))
    }

    func testSigningInFinishesAFailedFirstFetch() async throws {
        sync.setEnabled(true)
        engine.failsFetches = true
        await sync.fetchTask?.value
        let engineCount = engines.count

        engine.failsFetches = false
        sync.accountChanged(signedIn: true)
        await sync.fetchTask?.value

        XCTAssertEqual(engines.count, engineCount, "The same engine fetches again, no fresh start")
        XCTAssertTrue(engine.saves.contains(CloudSync.settingsRecordID))
    }
}
