import Foundation
import Observation
import os

/// Phone: keeps the putt captures the watch sends, one folder per capture under Documents,
/// and zips one up for sharing.
@MainActor
@Observable
final class PuttCaptureStore {
    struct File: Equatable {
        let name: String
        let bytes: Int
    }

    struct Capture: Identifiable, Equatable {
        /// The capture's UUID string, which is its folder name.
        let id: String
        let directory: URL
        /// Arrives first; nil until it has.
        let meta: PuttCapture.Meta?
        /// Files received so far and their sizes.
        let files: [File]
        /// When the capture started, or when its folder was made if the details are not here yet.
        let date: Date

        var totalBytes: Int { files.reduce(0) { $0 + $1.bytes } }
    }

    /// Newest first.
    private(set) var captures: [Capture] = []

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("putt-captures", isDirectory: true)
        reload()
    }

    /// Takes a file the watch sent. `metadata` names the capture and the file.
    func receive(file url: URL, metadata: [String: Any]?) {
        guard let id = metadata?[PuttCapture.captureKey] as? String, UUID(uuidString: id) != nil,
              let name = metadata?[PuttCapture.fileKey] as? String, PuttCapture.files.contains(name) else {
            Log.puttLab.error("Received a file that is not part of a capture: \(url.lastPathComponent)")
            try? FileManager.default.removeItem(at: url)
            return
        }
        let folder = directory.appendingPathComponent(id, isDirectory: true)
        let destination = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: url, to: destination)
            Log.puttLab.notice("Received \(name) of capture \(id)")
        } catch {
            Log.puttLab.error("Could not keep \(name) of capture \(id): \(String(describing: error))")
        }
        reload()
    }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])) ?? []
        captures = folders.compactMap { folder -> Capture? in
            guard folder.isDirectory, UUID(uuidString: folder.lastPathComponent) != nil else { return nil }
            let files = PuttCapture.files.compactMap { name -> File? in
                let size = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)[.size] as? Int
                return size.map { File(name: name, bytes: $0) }
            }
            let meta = (try? Data(contentsOf: folder.appendingPathComponent(PuttCapture.metaFile))).flatMap { try? PuttCapture.Meta(json: $0) }
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return Capture(id: folder.lastPathComponent, directory: folder, meta: meta, files: files, date: meta?.startDate ?? created)
        }
        .sorted { $0.date > $1.date }
    }

    /// Zips the capture's folder into a temporary file named after the capture's date and returns it.
    func zip(_ capture: Capture) throws -> URL {
        let name = capture.date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("putt-capture-\(name).zip")
        try? FileManager.default.removeItem(at: target)
        var coordinatorError: NSError?
        var copyError: Error?
        // Reading a folder "for uploading" gives a zip of it
        NSFileCoordinator().coordinate(readingItemAt: capture.directory, options: .forUploading, error: &coordinatorError) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: target)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        return target
    }

    func delete(_ capture: Capture) {
        do {
            try FileManager.default.removeItem(at: capture.directory)
        } catch {
            Log.puttLab.error("Could not delete capture \(capture.id): \(String(describing: error))")
        }
        reload()
    }
}
