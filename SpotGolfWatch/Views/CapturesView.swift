import SwiftUI

/// The captures on the watch, with their size, to delete once they have been pulled to a Mac.
struct CapturesView: View {
    struct Capture: Identifiable, Equatable {
        let id: String
        let url: URL
        let date: Date
        let inRound: Bool
        let segments: Int
        let bytes: Int64
    }

    @State private var captures: [Capture] = []

    var body: some View {
        List {
            if captures.isEmpty {
                Text("No captures")
                    .foregroundStyle(.secondary)
            }
            ForEach(captures) { capture in
                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(capture.inRound ? String(localized: "Round") : String(localized: "Putt Lab")) · \(capture.segments) segment(s) · \(capture.bytes, format: .byteCount(style: .file))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { delete(capture) }
                }
            }
        }
        .navigationTitle("Captures")
        .onAppear(perform: reload)
    }

    private func reload() {
        captures = Self.captures(in: PuttCaptureRecorder.directory)
    }

    private func delete(_ capture: Capture) {
        do {
            try FileManager.default.removeItem(at: capture.url)
            Log.puttLab.notice("Deleted capture \(capture.id)")
        } catch {
            Log.puttLab.error("Could not delete capture \(capture.id): \(String(describing: error))")
        }
        reload()
    }

    /// The captures under `root`, newest first. A capture's date is its first segment's start,
    /// or its folder's creation when no segment has details yet.
    static func captures(in root: URL) -> [Capture] {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey])) ?? []
        return folders.filter(\.isDirectory).map { folder in
            var date = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            var inRound = false
            var segments = 0
            var bytes: Int64 = 0
            let contents = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for segment in contents.filter(\.isDirectory).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                segments += 1
                if let data = try? Data(contentsOf: segment.appendingPathComponent(PuttCapture.metaFile)),
                   let meta = try? PuttCapture.Meta(json: data) {
                    if segments == 1 { date = meta.startDate }
                    inRound = inRound || meta.roundID != nil
                }
                let files = (try? manager.contentsOfDirectory(at: segment, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                for file in files {
                    bytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            return Capture(id: folder.lastPathComponent, url: folder, date: date, inRound: inRound, segments: segments, bytes: bytes)
        }
        .sorted { $0.date > $1.date }
    }
}
