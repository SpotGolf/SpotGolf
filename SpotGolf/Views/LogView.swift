import SwiftUI
import os

/// The app log: a round's lines from both devices, or the lines outside any round. Read in
/// time order, filtered by device and level, searched, and exported as a text file.
struct LogView: View {
    enum Scope {
        case round(Round)
        case outsideRounds
    }

    enum DeviceFilter: String, CaseIterable, Identifiable {
        case both, phone, watch
        var id: String { rawValue }
    }

    let scope: Scope

    @Environment(PhoneServices.self) private var services
    @State private var deviceFilter = DeviceFilter.both
    @State private var errorsOnly = false
    @State private var search = ""
    @State private var export: LogExport?

    var body: some View {
        List(filteredLines.indices, id: \.self) { index in
            LogLineRow(line: filteredLines[index])
        }
        .listStyle(.plain)
        .overlay {
            if filteredLines.isEmpty {
                ContentUnavailableView("No Log Lines", systemImage: "doc.text",
                                       description: Text(lines.isEmpty ? "Nothing has been recorded yet." : "Nothing matches the filter."))
            }
        }
        .searchable(text: $search, prompt: "Search messages")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Device", selection: $deviceFilter) {
                        Text("Phone and Watch").tag(DeviceFilter.both)
                        Text("Phone").tag(DeviceFilter.phone)
                        Text("Watch").tag(DeviceFilter.watch)
                    }
                    Toggle("Errors Only", isOn: $errorsOnly)
                } label: {
                    Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("LogFilter")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportLog()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("ExportLog")
                .disabled(lines.isEmpty)
            }
        }
        .sheet(item: $export) { export in
            ShareSheet(items: [export.url])
                .presentationDetents([.medium, .large])
        }
    }

    private var title: LocalizedStringKey {
        switch scope {
        case .round: "Round Log"
        case .outsideRounds: "Log"
        }
    }

    private var roundID: UUID? {
        if case .round(let round) = scope { return round.id }
        return nil
    }

    /// Every line in the scope. Reads `revision` so the list reloads as lines arrive.
    private var lines: [LogLine] {
        _ = services.logStore.revision
        return services.logStore.lines(for: roundID)
    }

    private var isFiltering: Bool {
        deviceFilter != .both || errorsOnly
    }

    private var filteredLines: [LogLine] {
        lines.filter { line in
            switch deviceFilter {
            case .both: break
            case .phone where line.device != .phone: return false
            case .watch where line.device != .watch: return false
            default: break
            }
            if errorsOnly, !line.level.isFailure { return false }
            if !search.isEmpty, !line.message.localizedCaseInsensitiveContains(search),
               !line.category.localizedCaseInsensitiveContains(search) { return false }
            return true
        }
    }

    /// Writes every line in the scope to a temporary text file and opens the share panel.
    private func exportLog() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try LogStore.text(lines).write(to: url, atomically: true, encoding: .utf8)
            export = LogExport(url: url)
        } catch {
            Log.export.error("Could not write log export: \(String(describing: error))")
        }
    }

    private var fileName: String {
        let date: Date
        switch scope {
        case .round(let round): date = round.date
        case .outsideRounds: date = Date()
        }
        let day = date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "spotgolf-log-\(day).txt"
    }
}

private struct LogExport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct LogLineRow: View {
    let line: LogLine

    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .standard)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).secondFraction(.fractional(3))

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(line.timestamp.formatted(Self.timeFormat))
                    .monospacedDigit()
                Image(systemName: line.device == .watch ? "applewatch" : "iphone")
                    .accessibilityLabel(line.device == .watch ? "Watch" : "Phone")
                Text(verbatim: line.category)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(verbatim: line.message)
                .font(line.level == .debug ? .footnote : .subheadline)
                .foregroundStyle(messageColor)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var messageColor: Color {
        switch line.level {
        case .debug: .secondary
        case .notice: .primary
        case .error, .fault: .red
        }
    }
}
