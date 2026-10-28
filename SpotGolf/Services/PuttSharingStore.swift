import Foundation
import Observation
import os

/// The phone's side of Putt Data Sharing: the player's consent and equipment profile, the
/// sessions the watch sent, and their upload to CloudKit. Sessions are kept in a small index
/// file; an archive waits in `pending/` until it is uploaded. See
/// `plans/2026-10-27-putt-data-sharing.md`, sections 1 and 3.4.
@MainActor
@Observable
final class PuttSharingStore {
    struct Session: Codable, Identifiable, Equatable {
        enum State: String, Codable {
            /// The watch finished it; its file has not arrived.
            case onWatch
            case onPhone
            case uploading
            case uploaded
            /// CloudKit is full until the developer pulls.
            case waitingToUpload
            case failed
        }

        let id: UUID
        var date: Date
        var drillsFinished: Int
        var size: Int64
        var hasLocation: Bool
        var state: State
    }

    /// Every session, newest first.
    private(set) var sessions: [Session] = []
    /// The phone has no iCloud account, so nothing uploads.
    private(set) var noAccount = false

    /// How long after a failed upload the next try starts. The last one repeats.
    static let retryDelays: [TimeInterval] = [60, 5 * 60, 15 * 60, 60 * 60]
    /// How long after CloudKit said it is full the next try starts.
    static let fullRetryDelay: TimeInterval = 60 * 60

    /// Told when consent or the profile change, so the watch can be sent them.
    @ObservationIgnored var onSettingsChanged: ((PhoneSettingsMessage) -> Void)?

    @ObservationIgnored private let cloud: PuttSharingCloud
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let root: URL
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var isUploading = false

    init(cloud: PuttSharingCloud, defaults: UserDefaults = .standard, root: URL = PuttSharingStore.directory) {
        self.cloud = cloud
        self.defaults = defaults
        self.root = root
        load()
        // An upload cut short by a quit starts over
        for index in sessions.indices where sessions[index].state == .uploading {
            sessions[index].state = .onPhone
        }
        loadSettings()
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("putt-sharing", isDirectory: true)
    }

    private var indexFile: URL { root.appendingPathComponent("sessions.json") }
    private var pending: URL { root.appendingPathComponent("pending", isDirectory: true) }
    private var deletionsFile: URL { root.appendingPathComponent("deletions.json") }

    private func archive(for id: UUID) -> URL {
        pending.appendingPathComponent("\(id.uuidString).aar")
    }

    // MARK: - Consent and profile

    /// The consent version the player agreed to, or nil.
    private(set) var consentVersion: Int?

    /// The random ID shared sessions carry, made at consent.
    private(set) var sharerID: UUID?

    var equipment = PuttSharing.Equipment() {
        didSet {
            guard equipment != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(equipment), forKey: SettingsKey.puttSharingEquipment)
            settingsChanged()
        }
    }

    var uploadsOnCellular = false {
        didSet {
            defaults.set(uploadsOnCellular, forKey: SettingsKey.puttSharingCellular)
            if uploadsOnCellular { uploadNext() }
        }
    }

    /// The player agreed to the current consent.
    var hasConsent: Bool {
        (consentVersion ?? 0) >= PuttSharing.consentVersion
    }

    private func loadSettings() {
        consentVersion = defaults.object(forKey: SettingsKey.puttSharingConsent) as? Int
        sharerID = defaults.string(forKey: SettingsKey.puttSharingSharerID).flatMap(UUID.init(uuidString:))
        equipment = defaults.data(forKey: SettingsKey.puttSharingEquipment)
            .flatMap { try? JSONDecoder().decode(PuttSharing.Equipment.self, from: $0) } ?? PuttSharing.Equipment()
        uploadsOnCellular = defaults.bool(forKey: SettingsKey.puttSharingCellular)
    }

    /// "I agree": the current consent, and a sharer ID if there is none.
    func agree() {
        consentVersion = PuttSharing.consentVersion
        defaults.set(PuttSharing.consentVersion, forKey: SettingsKey.puttSharingConsent)
        if sharerID == nil {
            newSharerID()
        }
        Log.puttSharing.notice("Putt Data Sharing consent \(PuttSharing.consentVersion) given")
        settingsChanged()
        uploadNext()
    }

    private func newSharerID() {
        let id = UUID()
        sharerID = id
        defaults.set(id.uuidString, forKey: SettingsKey.puttSharingSharerID)
    }

    /// What the watch needs: nothing before consent.
    var settingsMessage: PhoneSettingsMessage {
        hasConsent
            ? PhoneSettingsMessage(consentVersion: consentVersion, sharerID: sharerID, equipment: equipment)
            : PhoneSettingsMessage(consentVersion: nil, sharerID: nil, equipment: nil)
    }

    private func settingsChanged() {
        onSettingsChanged?(settingsMessage)
    }

    // MARK: - From the watch

    /// The watch finished a session; its file is on its way.
    func noticeArrived(_ notice: PuttSessionNotice) {
        guard !sessions.contains(where: { $0.id == notice.sessionID }) else { return }
        sessions.append(Session(id: notice.sessionID, date: notice.date, drillsFinished: notice.drillsFinished,
                                size: notice.size, hasLocation: notice.hasLocation, state: .onWatch))
        save()
    }

    /// A session's archive arrived from the watch. The store takes the file.
    func fileArrived(_ url: URL, metadata: [String: Any]) {
        guard let id = (metadata[PuttSharing.FileKey.sessionID] as? String).flatMap(UUID.init(uuidString:)) else {
            Log.puttSharing.error("A file with no session arrived")
            try? FileManager.default.removeItem(at: url)
            return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].state != .onWatch {
            // Sent again after the first copy arrived
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: archive(for: id))
            try FileManager.default.moveItem(at: url, to: archive(for: id))
        } catch {
            Log.puttSharing.error("Could not keep session \(id): \(String(describing: error))")
            return
        }
        let date = (metadata[PuttSharing.FileKey.date] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        let session = Session(id: id, date: date,
                              drillsFinished: metadata[PuttSharing.FileKey.drillsFinished] as? Int ?? 0,
                              size: size, hasLocation: metadata[PuttSharing.FileKey.hasLocation] as? Bool ?? false,
                              state: .onPhone)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        save()
        Log.puttSharing.notice("Session \(id) arrived, \(size) bytes")
        uploadNext()
    }

    // MARK: - Upload

    /// Uploads the oldest session waiting, one at a time, then the next.
    func uploadNext() {
        guard !isUploading, hasConsent, let sharerID,
              let session = sessions.last(where: { [.onPhone, .failed, .waitingToUpload].contains($0.state) }) else { return }
        isUploading = true
        retryTask?.cancel()
        setState(.uploading, for: session.id)
        let upload = PuttSessionUpload(sessionID: session.id, sharerID: sharerID, appVersion: AppVersion.text(),
                                       date: session.date, size: session.size, file: archive(for: session.id))
        let cellular = uploadsOnCellular
        let cloud = self.cloud
        Task {
            let result: Result<Void, Error>
            if await cloud.isAccountAvailable() {
                do {
                    try await cloud.upload(upload, cellular: cellular)
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(PuttSharingCloudError.noAccount)
            }
            self.uploadFinished(session.id, result)
        }
    }

    private func uploadFinished(_ id: UUID, _ result: Result<Void, Error>) {
        isUploading = false
        switch result {
        case .success:
            failures = 0
            noAccount = false
            try? FileManager.default.removeItem(at: archive(for: id))
            setState(.uploaded, for: id)
            Log.puttSharing.notice("Session \(id) uploaded")
            uploadNext()
        case .failure(PuttSharingCloudError.full):
            setState(.waitingToUpload, for: id)
            Log.puttSharing.notice("Session \(id) waits: CloudKit is full")
            retry(after: Self.fullRetryDelay)
        case .failure(PuttSharingCloudError.noAccount):
            noAccount = true
            setState(.onPhone, for: id)
        case .failure(let error):
            setState(.failed, for: id)
            Log.puttSharing.error("Session \(id) upload failed: \(String(describing: error))")
            retry(after: Self.retryDelays[min(failures, Self.retryDelays.count - 1)])
            failures += 1
        }
    }

    private func retry(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.uploadNext()
        }
    }

    // MARK: - Delete

    /// A deletion for CloudKit, kept until it is saved there.
    private struct Deletion: Codable, Equatable {
        let sharerID: UUID
        let sessionID: UUID?
    }

    /// Deletes a session here and in CloudKit, and asks the developer's next pull to delete it
    /// from the Mac.
    func delete(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        sessions.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: archive(for: id))
        save()
        // One uploading may still reach CloudKit
        if [.uploaded, .uploading].contains(session.state), let sharerID {
            addDeletion(Deletion(sharerID: sharerID, sessionID: id), sessionIDs: [id])
        }
        Log.puttSharing.notice("Session \(id) deleted")
    }

    /// Delete all my data: every session here, in CloudKit and, at the developer's next pull, on
    /// the Mac. A new sharer ID follows.
    func deleteAll() {
        let uploaded = sessions.filter { [.uploaded, .uploading].contains($0.state) }.map(\.id)
        if let sharerID {
            addDeletion(Deletion(sharerID: sharerID, sessionID: nil), sessionIDs: uploaded)
        }
        sessions = []
        try? FileManager.default.removeItem(at: pending)
        save()
        if hasConsent {
            newSharerID()
            settingsChanged()
        }
        Log.puttSharing.notice("All shared putt data deleted")
    }

    private func addDeletion(_ deletion: Deletion, sessionIDs: [UUID]) {
        var waiting = loadDeletions()
        waiting.append(deletion)
        saveDeletions(waiting)
        let cloud = self.cloud
        Task {
            try? await cloud.deleteSessions(sessionIDs)
            self.sendDeletions()
        }
    }

    /// Saves the deletions waiting to CloudKit; the ones that fail wait for the next launch.
    func sendDeletions() {
        let waiting = loadDeletions()
        guard !waiting.isEmpty else { return }
        let cloud = self.cloud
        Task {
            var failed: [Deletion] = []
            for deletion in waiting {
                do {
                    try await cloud.saveDeletion(sharerID: deletion.sharerID, sessionID: deletion.sessionID)
                } catch {
                    Log.puttSharing.error("Could not save a deletion: \(String(describing: error))")
                    failed.append(deletion)
                }
            }
            // Deletions added while these were saving stay too
            let added = self.loadDeletions().filter { !waiting.contains($0) }
            self.saveDeletions(failed + added)
        }
    }

    // MARK: - Files

    private func setState(_ state: Session.State, for id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = state
        save()
    }

    private func load() {
        sessions = (try? Data(contentsOf: indexFile))
            .flatMap { try? JSONDecoder().decode([Session].self, from: $0) } ?? []
    }

    private func save() {
        sessions.sort { $0.date > $1.date }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(sessions).write(to: indexFile)
        } catch {
            Log.puttSharing.error("Could not save the sessions: \(String(describing: error))")
        }
    }

    private func loadDeletions() -> [Deletion] {
        (try? Data(contentsOf: deletionsFile)).flatMap { try? JSONDecoder().decode([Deletion].self, from: $0) } ?? []
    }

    private func saveDeletions(_ deletions: [Deletion]) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? JSONEncoder().encode(deletions).write(to: deletionsFile)
    }
}
