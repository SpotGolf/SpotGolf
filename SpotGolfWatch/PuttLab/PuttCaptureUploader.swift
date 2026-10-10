import Foundation
import Observation
import os

/// Sends finished captures to the phone, one file at a time through WatchConnectivity, and
/// deletes each file once it has arrived. Files that fail are sent again at the next launch
/// or the next capture.
@MainActor
@Observable
final class PuttCaptureUploader {
    /// Files queued and not yet on the phone.
    private(set) var pendingFiles = 0

    private let transport: WatchConnectivityTransport?
    private let directory: URL

    init(transport: WatchConnectivityTransport?, directory: URL) {
        self.transport = transport
        self.directory = directory
        transport?.onFileTransferFinished = { [weak self] url, metadata, error in
            self?.finished(url, metadata: metadata, error: error)
        }
    }

    /// Queues every file of the capture in `captureDirectory`.
    func enqueue(_ captureDirectory: URL) {
        let id = captureDirectory.lastPathComponent
        let outstanding = Set(transport?.outstandingFileTransferURLs.map(\.standardizedFileURL.path) ?? [])
        for name in PuttCapture.files {
            let url = captureDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path),
                  !outstanding.contains(url.standardizedFileURL.path) else { continue }
            if transport?.transferFile(url, metadata: [PuttCapture.captureKey: id, PuttCapture.fileKey: name]) == true {
                Log.puttLab.notice("Queued \(name) of capture \(id) for the phone")
            }
        }
        refresh()
    }

    /// Queues the files of every capture left on the watch, except the one recording.
    func resumePending(except recording: URL? = nil) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for url in urls where url.isDirectory && url.lastPathComponent != recording?.lastPathComponent {
            enqueue(url)
        }
        refresh()
    }

    private func finished(_ url: URL, metadata: [String: Any]?, error: Error?) {
        let name = url.lastPathComponent
        if let error {
            Log.puttLab.error("Transfer of \(name) failed: \(String(describing: error))")
        } else {
            Log.puttLab.notice("Transfer of \(name) done")
            try? FileManager.default.removeItem(at: url)
            let folder = url.deletingLastPathComponent()
            if let left = try? FileManager.default.contentsOfDirectory(atPath: folder.path), left.isEmpty {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        refresh()
    }

    private func refresh() {
        pendingFiles = transport?.outstandingFileTransferURLs.count ?? 0
    }
}
