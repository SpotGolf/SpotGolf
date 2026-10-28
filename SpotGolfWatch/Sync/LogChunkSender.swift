import Foundation
import os

/// Watch: closes the log file into chunks and sends each to the phone with `transferFile`,
/// which the system retries until it arrives, even if either app quits first. A chunk closes
/// when it reaches `maxChunkBytes`, when its first line is `maxChunkAge` old, when a round
/// ends, and when the phone asks. It is deleted once it arrives. Lines about sending a chunk
/// are logged only on failure, so a sent chunk does not start the next one.
@MainActor
final class LogChunkSender {
    static let maxChunkBytes = 50_000
    static let maxChunkAge: TimeInterval = 5 * 60
    /// Chunks kept while the phone can't be reached. Past it, the oldest are deleted.
    static let maxOutboxBytes = 1_000_000
    /// The watch's log file. Chunks close well before it fills; the limit only guards against
    /// a file that never closes.
    static let maxFileBytes = 1_000_000

    /// Application Support/Logs/outbox.
    static var defaultOutbox: URL {
        LogFile.defaultDirectory.appendingPathComponent("outbox", isDirectory: true)
    }

    let file: LogFile
    let outbox: URL
    private let transport: SyncTransport
    private let maxChunkAge: TimeInterval
    private var ageTimer: Timer?

    init(file: LogFile, transport: SyncTransport, outbox: URL = LogChunkSender.defaultOutbox,
         maxChunkAge: TimeInterval = LogChunkSender.maxChunkAge) {
        self.file = file
        self.transport = transport
        self.outbox = outbox
        self.maxChunkAge = maxChunkAge
    }

    /// After each line: a full chunk closes now, and a new one closes once it is old enough.
    func lineWritten() {
        if file.currentSize >= Self.maxChunkBytes {
            closeChunk()
        } else if ageTimer == nil {
            ageTimer = Timer.scheduledTimer(withTimeInterval: maxChunkAge, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.closeChunk() }
            }
        }
    }

    /// Moves what the log holds into the outbox and sends it. Nothing happens for an empty log.
    func closeChunk(now: Date = Date()) {
        ageTimer?.invalidate()
        ageTimer = nil
        let chunk = outbox.appendingPathComponent(LogChunk.fileName(at: now))
        guard file.moveCurrent(to: chunk) else { return }
        send(chunk)
        trimOutbox()
    }

    /// Whether `metadata` is a chunk's. A chunk that arrived is deleted; one that failed stays
    /// for the next launch.
    @discardableResult
    func transferFinished(_ metadata: [String: Any], error: Error?) -> Bool {
        guard let name = metadata[LogChunk.FileKey.chunk] as? String else { return false }
        if let error {
            Log.sync.error("Sending log chunk \(name) failed: \(String(describing: error))")
            return true
        }
        try? FileManager.default.removeItem(at: outbox.appendingPathComponent(name))
        return true
    }

    /// At launch: sends again every chunk not on its way, and starts the age timer for lines
    /// the last launch left in the log.
    func recoverAtLaunch() {
        let sending = Set(transport.outstandingFileTransfers.compactMap { $0[LogChunk.FileKey.chunk] as? String })
        for chunk in chunks() where !sending.contains(chunk.lastPathComponent) {
            send(chunk)
        }
        if file.currentSize > 0 {
            lineWritten()
        }
    }

    /// The chunks waiting, oldest first.
    func chunks() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == LogFile.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func send(_ chunk: URL) {
        transport.transferFile(chunk, metadata: [LogChunk.FileKey.chunk: chunk.lastPathComponent])
    }

    /// Deletes the oldest chunks past `maxOutboxBytes`.
    private func trimOutbox() {
        var chunks = chunks().map { ($0, (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        var total = chunks.reduce(0) { $0 + $1.1 }
        while total > Self.maxOutboxBytes, chunks.count > 1 {
            let (oldest, size) = chunks.removeFirst()
            try? FileManager.default.removeItem(at: oldest)
            total -= size
            Log.sync.error("Log outbox full; deleted chunk \(oldest.lastPathComponent)")
        }
    }
}
