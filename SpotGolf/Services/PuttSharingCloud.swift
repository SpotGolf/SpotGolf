import CloudKit
import Foundation

/// Where shared drill sessions go: the app's CloudKit public database, which the developer
/// pulls from with `Scripts/pull-shared-putts.py`. See `plans/2026-10-27-putt-data-sharing.md`,
/// section 3.4.
protocol PuttSharingCloud: Sendable {
    /// True when the phone has an iCloud account, which uploads need.
    func isAccountAvailable() async -> Bool
    /// Saves a session's archive.
    func upload(_ upload: PuttSessionUpload, cellular: Bool) async throws
    /// Deletes sessions still in CloudKit, by session ID. Ones already pulled are gone, which is fine.
    func deleteSessions(_ sessionIDs: [UUID]) async throws
    /// Asks the developer's next pull to delete one session, or every session of the sharer.
    func saveDeletion(sharerID: UUID, sessionID: UUID?) async throws
}

struct PuttSessionUpload: Sendable {
    let sessionID: UUID
    let sharerID: UUID
    let appVersion: String
    let date: Date
    let size: Int64
    let file: URL
}

/// Why an upload failed.
enum PuttSharingCloudError: Error {
    /// The app's CloudKit storage is full until the developer pulls; try again later.
    case full
    case noAccount
}

/// For UI tests, which run without iCloud: every upload is kept on the phone.
struct NoPuttSharingCloud: PuttSharingCloud {
    func isAccountAvailable() async -> Bool { false }
    func upload(_ upload: PuttSessionUpload, cellular: Bool) async throws { throw PuttSharingCloudError.noAccount }
    func deleteSessions(_ sessionIDs: [UUID]) async throws {}
    func saveDeletion(sharerID: UUID, sessionID: UUID?) async throws {}
}

/// Sessions as `PuttSession` records and deletions as `PuttDeletion` records in the public
/// database. Their security roles, set in the CloudKit console: signed-in users create, only
/// the creator reads and writes.
final class CloudKitPuttSharing: PuttSharingCloud {
    static let sessionType = "PuttSession"
    static let deletionType = "PuttDeletion"

    private let container: CKContainer

    init(container: CKContainer = CKContainer(identifier: CloudKitPinSharing.containerID)) {
        self.container = container
    }

    private var database: CKDatabase { container.publicCloudDatabase }

    func isAccountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    func upload(_ upload: PuttSessionUpload, cellular: Bool) async throws {
        let record = CKRecord(recordType: Self.sessionType, recordID: CKRecord.ID(recordName: upload.sessionID.uuidString))
        record["sessionID"] = upload.sessionID.uuidString
        record["sharerID"] = upload.sharerID.uuidString
        record["appVersion"] = upload.appVersion
        record["createdDate"] = upload.date
        record["size"] = upload.size
        record["archive"] = CKAsset(fileURL: upload.file)
        let configuration = CKOperation.Configuration()
        configuration.allowsCellularAccess = cellular
        configuration.qualityOfService = .utility
        do {
            try await database.configuredWith(configuration: configuration) { database in
                _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            }
        } catch let error as CKError where [.quotaExceeded, .limitExceeded].contains(error.code) {
            throw PuttSharingCloudError.full
        } catch let error as CKError where error.code == .notAuthenticated {
            throw PuttSharingCloudError.noAccount
        }
    }

    func deleteSessions(_ sessionIDs: [UUID]) async throws {
        guard !sessionIDs.isEmpty else { return }
        let ids = sessionIDs.map { CKRecord.ID(recordName: $0.uuidString) }
        let (_, results) = try await database.modifyRecords(saving: [], deleting: ids)
        for case .failure(let error) in results.values {
            // Pulled and deleted by the developer already
            if (error as? CKError)?.code == .unknownItem { continue }
            throw error
        }
    }

    func saveDeletion(sharerID: UUID, sessionID: UUID?) async throws {
        let record = CKRecord(recordType: Self.deletionType)
        record["sharerID"] = sharerID.uuidString
        record["sessionID"] = sessionID?.uuidString
        record["createdDate"] = Date()
        _ = try await database.modifyRecords(saving: [record], deleting: [])
    }
}
