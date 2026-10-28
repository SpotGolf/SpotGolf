import Foundation
import os

/// The app's log as text files, one line each, in `directory`: `spotgolf.log` is written now,
/// and `spotgolf.1.log` … are older, `1` the newest. Writes go straight to the file from any
/// thread. When a write would take the current file past `maxFileBytes`, the files move down
/// one and the oldest past `keptFiles` is deleted. See plans/2026-10-28-unified-log.md.
final class LogFile: Sendable {
    static let name = "spotgolf"
    static let fileExtension = "log"

    /// The phone keeps 5 files of 2 MB, 10 MB in all.
    static let phoneMaxFileBytes = 2_000_000
    static let phoneKeptFiles = 4

    /// Application Support/Logs.
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    let directory: URL
    let maxFileBytes: Int
    /// Older files kept besides the current one.
    let keptFiles: Int

    private struct State {
        var handle: FileHandle?
        var size = 0
        /// Set after a failure is reported, so a broken file is reported once, not per line.
        var hasReportedFailure = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// The file's own failures go to the unified log only, so it never logs about itself into itself.
    private let logger = Logger(subsystem: Log.subsystem, category: "storage")

    init(directory: URL = LogFile.defaultDirectory, maxFileBytes: Int = LogFile.phoneMaxFileBytes,
         keptFiles: Int = LogFile.phoneKeptFiles) {
        self.directory = directory
        self.maxFileBytes = maxFileBytes
        self.keptFiles = keptFiles
    }

    deinit {
        try? state.withLock { $0.handle }?.close()
    }

    /// The file written now.
    var currentURL: URL {
        url(index: 0)
    }

    func url(index: Int) -> URL {
        let name = index == 0 ? Self.name : "\(Self.name).\(index)"
        return directory.appendingPathComponent(name).appendingPathExtension(Self.fileExtension)
    }

    /// `Log`'s sink.
    func write(_ line: LogLine) {
        append(Data((line.text + "\n").utf8))
    }

    /// Appends whole lines, such as a chunk of the watch's log.
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        state.withLock { state in
            if state.handle != nil, state.size > 0, state.size + data.count > maxFileBytes {
                rotate(&state)
            }
            do {
                let handle = try openHandle(&state)
                try handle.write(contentsOf: data)
                state.size += data.count
            } catch {
                report(error, action: "write the log", state: &state)
                try? state.handle?.close()
                state.handle = nil
            }
        }
    }

    /// The bytes in the current file.
    var currentSize: Int {
        state.withLock { state in
            if state.handle == nil { state.size = Self.size(of: currentURL) }
            return state.size
        }
    }

    /// Every file there is, oldest first.
    func files() -> [URL] {
        (0...keptFiles).reversed().map(url(index:)).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Every line there is, oldest file first.
    func allData() -> Data {
        files().reduce(into: Data()) { data, url in
            data.append((try? Data(contentsOf: url)) ?? Data())
        }
    }

    /// Moves the current file to `destination`, so the next line starts a new one. False when
    /// the current file is empty or could not be moved.
    func moveCurrent(to destination: URL) -> Bool {
        state.withLock { state in
            try? state.handle?.close()
            state.handle = nil
            guard Self.size(of: currentURL) > 0 else { return false }
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: currentURL, to: destination)
                state.size = 0
                return true
            } catch {
                report(error, action: "move the log to \(destination.lastPathComponent)", state: &state)
                return false
            }
        }
    }

    // MARK: - Private

    private func openHandle(_ state: inout State) throws -> FileHandle {
        if let handle = state.handle { return handle }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: currentURL.path) {
            manager.createFile(atPath: currentURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: currentURL)
        state.size = Int(try handle.seekToEnd())
        state.handle = handle
        state.hasReportedFailure = false
        // A full file left by the last launch moves down before the first line is added
        if state.size >= maxFileBytes {
            rotate(&state)
            return try openHandle(&state)
        }
        return handle
    }

    /// Moves each file down one, deleting the oldest. The current file is gone afterwards.
    private func rotate(_ state: inout State) {
        try? state.handle?.close()
        state.handle = nil
        state.size = 0
        let manager = FileManager.default
        try? manager.removeItem(at: url(index: keptFiles))
        for index in stride(from: keptFiles - 1, through: 0, by: -1) {
            let from = url(index: index)
            guard manager.fileExists(atPath: from.path) else { continue }
            try? manager.moveItem(at: from, to: url(index: index + 1))
        }
        // With no older files kept, the current one is deleted
        try? manager.removeItem(at: currentURL)
    }

    private func report(_ error: Error, action: String, state: inout State) {
        guard !state.hasReportedFailure else { return }
        state.hasReportedFailure = true
        logger.error("Could not \(action, privacy: .public): \(String(describing: error), privacy: .public)")
    }

    private static func size(of url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }
}
