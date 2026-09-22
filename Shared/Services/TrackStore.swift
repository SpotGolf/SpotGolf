import Foundation
import CoreLocation

/// Stores every raw GPS fix of a round in one binary file per round and device.
/// A file is a 4-byte version header followed by one `TrackPoint` record per fix.
@MainActor
class TrackStore: ObservableObject {
    static let flushThreshold = 10
    nonisolated static let fileExtension = "track"

    private static let headerSize = MemoryLayout<Int32>.size

    private let directory: URL

    // Finished tracks waiting to be transferred to the phone
    private var outboxDirectory: URL {
        directory.appendingPathComponent("outbox")
    }

    // Fixes not yet written to `pendingURL`
    private var pendingPoints: [TrackPoint] = []
    private var pendingURL: URL?

    // Makes outbox segment names unique even within one millisecond
    private var segmentCounter = 0

    /// Bumped whenever a received segment adds points, so views can reload tracks.
    @Published private(set) var revision = 0

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = docs.appendingPathComponent("tracks")
        }
    }

    func fileURL(for roundID: UUID, source: TrackSource) -> URL {
        directory.appendingPathComponent("\(roundID.uuidString)_\(source.rawValue).\(Self.fileExtension)")
    }

    /// Reads the round and device out of a track file name.
    nonisolated static func parseFileName(_ url: URL) -> (roundID: UUID, source: TrackSource)? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
        guard parts.count >= 2,
              let roundID = UUID(uuidString: String(parts[0])),
              let source = TrackSource(rawValue: String(parts[1])) else { return nil }
        return (roundID, source)
    }

    // MARK: - Recording

    func append(_ locations: [CLLocation], roundID: UUID, source: TrackSource = .current) {
        let url = fileURL(for: roundID, source: source)
        if pendingURL != url {
            flush()
            pendingURL = url
        }
        pendingPoints += locations.map { TrackPoint(location: $0) }
        if pendingPoints.count >= Self.flushThreshold {
            flush()
        }
    }

    func flush() {
        guard let url = pendingURL, !pendingPoints.isEmpty else { return }
        write(pendingPoints, to: url)
        pendingPoints.removeAll()
    }

    // MARK: - Reading

    func points(for roundID: UUID, source: TrackSource) -> [TrackPoint] {
        flush()
        return Self.readPoints(at: fileURL(for: roundID, source: source))
    }

    func deleteRound(_ roundID: UUID) {
        if let url = pendingURL, Self.parseFileName(url)?.roundID == roundID {
            pendingPoints.removeAll()
            pendingURL = nil
        }
        for url in trackFiles(in: directory) + trackFiles(in: outboxDirectory)
        where Self.parseFileName(url)?.roundID == roundID {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Transfer

    /// Moves this device's tracks into the outbox as segments, including the active
    /// round's: recording simply starts a fresh file, and the receiver merges segments,
    /// so a file is never appended to while it is being transferred.
    func moveTracksToOutbox() {
        flush()
        for url in trackFiles(in: directory) {
            guard let info = Self.parseFileName(url),
                  info.source == .current else { continue }
            segmentCounter += 1
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let name = "\(info.roundID.uuidString)_\(info.source.rawValue)_\(stamp)-\(segmentCounter).\(Self.fileExtension)"
            do {
                try FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: url, to: outboxDirectory.appendingPathComponent(name))
            } catch {
                print("Failed to move track to outbox: \(error)")
            }
        }
    }

    func outboxFiles() -> [URL] {
        trackFiles(in: outboxDirectory).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func removeOutboxFile(_ url: URL) {
        try? FileManager.default.removeItem(at: outboxDirectory.appendingPathComponent(url.lastPathComponent))
    }

    /// Merges a track file received from the other device into the stored track.
    /// Fixes already stored are skipped, so receiving the same file twice is harmless.
    func importSegment(from url: URL, roundID: UUID, source: TrackSource) {
        let existing = points(for: roundID, source: source)
        let known = Set(existing.map(\.timestamp))
        let fresh = Self.readPoints(at: url).filter { !known.contains($0.timestamp) }
        guard !fresh.isEmpty else { return }

        let merged = (existing + fresh).sorted { $0.timestamp < $1.timestamp }
        write(merged, to: fileURL(for: roundID, source: source), replacing: true)
        revision += 1
    }

    // MARK: - Files

    private static func readPoints(at url: URL) -> [TrackPoint] {
        guard let data = try? Data(contentsOf: url), data.count >= headerSize else { return [] }
        let version: Int32 = data.littleEndianInteger(at: 0)
        guard version == TrackPoint.fileVersion else { return [] }

        // A write that was cut short can leave part of a record at the end; it is skipped
        let count = (data.count - headerSize) / TrackPoint.recordSize
        return (0..<count).compactMap { index in
            let start = data.startIndex + headerSize + index * TrackPoint.recordSize
            return TrackPoint(record: data[start..<(start + TrackPoint.recordSize)])
        }
    }

    private func trackFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == Self.fileExtension }
    }

    private func write(_ points: [TrackPoint], to url: URL, replacing: Bool = false) {
        var records = Data(capacity: points.count * TrackPoint.recordSize)
        for point in points {
            records.append(point.record)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !replacing, FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                // Drop a partial record left by a write that was cut short, so new records stay aligned
                let size = try handle.seekToEnd()
                let partial = (size - UInt64(Self.headerSize)) % UInt64(TrackPoint.recordSize)
                if size >= UInt64(Self.headerSize), partial != 0 {
                    try handle.truncate(atOffset: size - partial)
                }
                try handle.write(contentsOf: records)
            } else {
                var header = Data()
                header.append(littleEndian: TrackPoint.fileVersion)
                try (header + records).write(to: url, options: .atomic)
            }
        } catch {
            print("Failed to save track: \(error)")
        }
    }
}
