import SwiftUI
import os

/// The putt captures the watch has sent, each shareable as a zip.
struct PuttCapturesView: View {
    @EnvironmentObject var store: PuttCaptureStore
    @State private var export: CaptureExport?
    @State private var exportError: String?

    var body: some View {
        List {
            if store.captures.isEmpty {
                Text("No captures yet. Record one on the watch's Putt Lab page; it is sent here when it stops.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.captures) { capture in
                row(capture)
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.delete(capture) }
                    }
            }
        }
        .navigationTitle("Putt Captures")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { store.reload() }
        .sheet(item: $export) { export in
            ShareSheet(items: [export.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func row(_ capture: PuttCaptureStore.Capture) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.date.formatted(date: .abbreviated, time: .shortened))
                Text(details(capture))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                share(capture)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Share capture")
        }
    }

    private func details(_ capture: PuttCaptureStore.Capture) -> String {
        var parts: [String] = []
        if let meta = capture.meta {
            if !meta.savesData {
                parts.append(meta.microphone ? "battery test, mic on" : "battery test, mic off")
            }
            if let duration = meta.duration {
                parts.append(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
            }
            if let start = meta.startBattery, let end = meta.endBattery, let duration = meta.duration, duration > 0 {
                let drop = (start - end) * 100
                parts.append(String(format: "%.0f%% to %.0f%%, %.1f pts/h", start * 100, end * 100, drop * 3600 / duration))
            }
            let count = { (label: PuttCapture.MarkLabel) in meta.marks.filter { $0.label == label }.count }
            parts.append("\(count(.putt)) putts, \(count(.practice)) practice, \(count(.ground)) ground")
            if meta.audio == nil { parts.append("no audio") }
        } else {
            parts.append("details not received yet")
        }
        parts.append("\(capture.files.count) of \(PuttCapture.files.count) files, \(ByteCountFormatter.string(fromByteCount: Int64(capture.totalBytes), countStyle: .file))")
        return parts.joined(separator: " · ")
    }

    private func share(_ capture: PuttCaptureStore.Capture) {
        do {
            export = CaptureExport(url: try store.zip(capture))
        } catch {
            Log.puttLab.error("Could not zip capture \(capture.id, privacy: .public): \(String(describing: error), privacy: .public)")
            exportError = error.localizedDescription
        }
    }
}

private struct CaptureExport: Identifiable {
    let id = UUID()
    let url: URL
}
