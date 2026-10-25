import CloudKit
import Foundation

/// `CloudSync`'s engine: a `CKSyncEngine` on the private database, passing its events to
/// `CloudSync` on the main actor.
@MainActor
final class CloudKitSyncEngine: CloudSyncEngine {
    private let delegate: Delegate
    private let engine: CKSyncEngine

    /// `state` is what an earlier engine saved through `CloudSync.engineStateChanged`, or nil.
    init(state: Data?, sync: CloudSync) {
        delegate = Delegate(sync: sync)
        let serialization = state.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let database = CKContainer(identifier: CloudSync.containerID).privateCloudDatabase
        engine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: serialization,
                                                         delegate: delegate))
    }

    func add(_ changes: [CloudSyncChange]) {
        engine.state.add(pendingRecordZoneChanges: changes.map { change in
            switch change {
            case .save(let id): .saveRecord(id)
            case .delete(let id): .deleteRecord(id)
            }
        })
    }

    func addZone() {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSync.zoneID))])
    }

    func fetchChanges() async throws {
        try await engine.fetchChanges()
    }

    private final class Delegate: CKSyncEngineDelegate {
        let sync: CloudSync

        init(sync: CloudSync) {
            self.sync = sync
        }

        func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
            switch event {
            case .stateUpdate(let update):
                let data = try? JSONEncoder().encode(update.stateSerialization)
                await sync.engineStateChanged(data)
            case .accountChange(let change):
                switch change.changeType {
                case .signIn: await sync.accountChanged(signedIn: true)
                case .signOut, .switchAccounts: await sync.accountChanged(signedIn: false)
                @unknown default: break
                }
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == CloudSync.zoneID }) {
                    await sync.zoneDeleted()
                }
            case .fetchedRecordZoneChanges(let changes):
                // The assets' files last until this returns, so `CloudSync` reads them in the call
                await sync.fetched(modifications: changes.modifications.map(\.record),
                                   deletions: changes.deletions.map { ($0.recordID, $0.recordType) })
            case .sentRecordZoneChanges(let sent):
                await sync.sent(saved: sent.savedRecords,
                                failed: sent.failedRecordSaves.map { ($0.record, $0.error) },
                                deleted: sent.deletedRecordIDs)
            case .didFetchChanges:
                await sync.fetchFinished()
            default:
                break
            }
        }

        func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                       syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
            let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [sync] id in
                await sync.record(for: id)
            }
        }
    }
}
