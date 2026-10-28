import Foundation
import os

/// Phone: adds each chunk of the watch's log to the phone's `LogFile` as it arrives. The watch
/// sends a chunk again when it was killed before hearing that it arrived, so the names of the
/// last `seenLimit` chunks are kept and a repeat is skipped.
@MainActor
final class LogChunkReceiver {
    static let seenLimit = 100
    static let seenKey = "logChunksReceived"

    private let file: LogFile
    private let defaults: UserDefaults

    init(file: LogFile, defaults: UserDefaults = .standard) {
        self.file = file
        self.defaults = defaults
    }

    /// Takes the chunk at `url`, which it owns, and deletes it.
    func receive(_ url: URL, name: String) {
        defer { try? FileManager.default.removeItem(at: url) }
        var seen = defaults.stringArray(forKey: Self.seenKey) ?? []
        guard !seen.contains(name) else {
            Log.sync.notice("Skipped log chunk \(name): already received")
            return
        }
        guard var data = try? Data(contentsOf: url) else {
            Log.sync.error("Could not read log chunk \(name)")
            return
        }
        if !data.isEmpty, data.last != UInt8(ascii: "\n") {
            data.append(UInt8(ascii: "\n"))
        }
        file.append(data)
        seen.append(name)
        defaults.set(Array(seen.suffix(Self.seenLimit)), forKey: Self.seenKey)
    }
}
