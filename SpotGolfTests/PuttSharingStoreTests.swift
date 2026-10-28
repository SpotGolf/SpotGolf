import XCTest
@testable import SpotGolf

/// A CloudKit stand-in that records what was asked of it.
private final class FakeCloud: PuttSharingCloud, @unchecked Sendable {
    var account = true
    var uploadError: Error?
    private(set) var uploads: [PuttSessionUpload] = []
    private(set) var deletedSessions: [UUID] = []
    private(set) var deletions: [(sharerID: UUID, sessionID: UUID?)] = []
    var deletionFails = false

    func isAccountAvailable() async -> Bool { account }

    func upload(_ upload: PuttSessionUpload, cellular: Bool) async throws {
        if let uploadError { throw uploadError }
        XCTAssertTrue(FileManager.default.fileExists(atPath: upload.file.path), "The archive is there to upload")
        uploads.append(upload)
    }

    func deleteSessions(_ sessionIDs: [UUID]) async throws {
        deletedSessions += sessionIDs
    }

    func saveDeletion(sharerID: UUID, sessionID: UUID?) async throws {
        if deletionFails { throw FakeTransportError() }
        deletions.append((sharerID, sessionID))
    }
}

@MainActor
final class PuttSharingStoreTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var cloud: FakeCloud!
    private var store: PuttSharingStore!
    private var sentSettings: [PhoneSettingsMessage] = []

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sharing-\(UUID().uuidString)", isDirectory: true)
        defaults = UserDefaults(suiteName: "PuttSharingStoreTests-\(UUID().uuidString)")
        cloud = FakeCloud()
        store = makeStore()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        store = nil
        try await super.tearDown()
    }

    private func makeStore() -> PuttSharingStore {
        let store = PuttSharingStore(cloud: cloud, defaults: defaults, root: root)
        store.onSettingsChanged = { [weak self] in self?.sentSettings.append($0) }
        return store
    }

    /// A session's archive as it arrives from the watch.
    private func arrive(_ id: UUID = UUID(), drills: Int = 8, bytes: Int = 1_000) throws -> UUID {
        let file = root.appendingPathComponent("incoming-\(id.uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: file)
        store.fileArrived(file, metadata: [PuttSharing.FileKey.sessionID: id.uuidString,
                                           PuttSharing.FileKey.date: 1_700_000_000.0,
                                           PuttSharing.FileKey.drillsFinished: drills,
                                           PuttSharing.FileKey.hasLocation: true])
        return id
    }

    /// Lets the store's upload and deletion tasks run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
    }

    private var pendingFiles: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("pending").path)) ?? []
    }

    // MARK: - Consent

    func testNothingIsSentToTheWatchBeforeConsent() {
        XCTAssertFalse(store.hasConsent)
        XCTAssertEqual(store.settingsMessage, PhoneSettingsMessage(consentVersion: nil, sharerID: nil, equipment: nil))
    }

    func testAgreeingMakesASharerIDAndTellsTheWatch() throws {
        store.agree()

        XCTAssertTrue(store.hasConsent)
        let sharerID = try XCTUnwrap(store.sharerID)
        XCTAssertEqual(sentSettings.last, PhoneSettingsMessage(consentVersion: PuttSharing.consentVersion,
                                                               sharerID: sharerID, equipment: PuttSharing.Equipment()))
        XCTAssertEqual(makeStore().sharerID, sharerID, "Kept across launches")
    }

    func testChangingTheProfileTellsTheWatch() {
        store.agree()
        store.equipment.putterHead = .mallet

        XCTAssertEqual(sentSettings.last?.equipment?.putterHead, .mallet)
        XCTAssertEqual(makeStore().equipment.putterHead, .mallet, "Kept across launches")
    }

    // MARK: - Sessions

    func testANoticeListsTheSessionAsOnTheWatch() {
        let id = UUID()
        store.noticeArrived(PuttSessionNotice(sessionID: id, date: Date(), drillsFinished: 3, size: 10, hasLocation: false))

        XCTAssertEqual(store.sessions.map(\.state), [.onWatch])
        XCTAssertEqual(store.sessions.first?.drillsFinished, 3)
    }

    func testAnArrivedSessionUploadsAndItsArchiveIsDeleted() async throws {
        store.agree()
        let id = try arrive(drills: 6)
        await settle()

        XCTAssertEqual(cloud.uploads.map(\.sessionID), [id])
        XCTAssertEqual(cloud.uploads.first?.sharerID, store.sharerID)
        XCTAssertEqual(store.sessions.first?.state, .uploaded)
        XCTAssertEqual(store.sessions.first?.drillsFinished, 6)
        XCTAssertTrue(store.sessions.first?.hasLocation == true)
        XCTAssertEqual(pendingFiles, [])
    }

    func testNoUploadBeforeConsent() async throws {
        _ = try arrive()
        await settle()

        XCTAssertEqual(cloud.uploads.count, 0)
        XCTAssertEqual(store.sessions.first?.state, .onPhone)
    }

    func testAFullCloudKeepsTheSessionWaiting() async throws {
        store.agree()
        cloud.uploadError = PuttSharingCloudError.full
        _ = try arrive()
        await settle()

        XCTAssertEqual(store.sessions.first?.state, .waitingToUpload)
        XCTAssertEqual(pendingFiles.count, 1, "The archive stays for the next try")
    }

    func testNoAccountKeepsTheSessionOnThePhone() async throws {
        store.agree()
        cloud.account = false
        _ = try arrive()
        await settle()

        XCTAssertTrue(store.noAccount)
        XCTAssertEqual(store.sessions.first?.state, .onPhone)
    }

    func testAFailedUploadIsMarkedAndKept() async throws {
        store.agree()
        cloud.uploadError = FakeTransportError()
        _ = try arrive()
        await settle()

        XCTAssertEqual(store.sessions.first?.state, .failed)
        XCTAssertEqual(pendingFiles.count, 1)
    }

    func testTheSameFileSentTwiceIsKeptOnce() async throws {
        store.agree()
        let id = try arrive()
        await settle()
        _ = try arrive(id)
        await settle()

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(cloud.uploads.count, 1)
    }

    func testSessionsOutliveTheApp() async throws {
        store.agree()
        let id = try arrive()
        await settle()

        XCTAssertEqual(makeStore().sessions.map(\.id), [id])
    }

    // MARK: - Delete

    func testDeletingAnUploadedSessionDeletesItInCloudKitAndOnTheMac() async throws {
        store.agree()
        let id = try arrive()
        await settle()

        store.delete(id)
        await settle()

        XCTAssertEqual(store.sessions.count, 0)
        XCTAssertEqual(cloud.deletedSessions, [id])
        XCTAssertEqual(cloud.deletions.map(\.sessionID), [id])
        XCTAssertEqual(cloud.deletions.first?.sharerID, store.sharerID)
    }

    func testDeletingASessionNotUploadedStaysOnThePhone() async throws {
        let id = try arrive()

        store.delete(id)
        await settle()

        XCTAssertEqual(pendingFiles, [])
        XCTAssertEqual(cloud.deletions.count, 0)
    }

    func testDeleteAllAsksForEverySessionOfTheSharerAndMakesANewID() async throws {
        store.agree()
        let sharerID = try XCTUnwrap(store.sharerID)
        let first = try arrive()
        await settle()
        let second = try arrive()
        await settle()

        store.deleteAll()
        await settle()

        XCTAssertEqual(store.sessions.count, 0)
        XCTAssertEqual(Set(cloud.deletedSessions), [first, second])
        XCTAssertEqual(cloud.deletions.count, 1)
        XCTAssertEqual(cloud.deletions.first?.sharerID, sharerID)
        XCTAssertNil(cloud.deletions.first?.sessionID, "All of the sharer's sessions")
        XCTAssertNotEqual(store.sharerID, sharerID)
        XCTAssertEqual(sentSettings.last?.sharerID, store.sharerID, "The watch gets the new ID")
    }

    func testADeletionThatFailsIsSentAtTheNextLaunch() async throws {
        store.agree()
        let id = try arrive()
        await settle()
        cloud.deletionFails = true

        store.delete(id)
        await settle()
        XCTAssertEqual(cloud.deletions.count, 0)

        cloud.deletionFails = false
        let relaunched = makeStore()
        relaunched.sendDeletions()
        await settle()

        XCTAssertEqual(cloud.deletions.map(\.sessionID), [id])
    }
}
