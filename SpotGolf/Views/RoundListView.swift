import SwiftUI

struct RoundListView: View {
    @Binding var navigationPath: NavigationPath
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var trackStore: TrackStore
    @EnvironmentObject var guessStore: GuessStore
    @State private var showCourseSelection = false
    @State private var showSettings = false
    @State private var roundToDelete: Round?
    @State private var export: RoundExport?

    var body: some View {
        List {
            if let active = roundStore.activeRound {
                Section("Active Round") {
                    NavigationLink(value: active.id) {
                        RoundRow(round: active)
                    }
                }
            }

            Section("Past Rounds") {
                ForEach(roundStore.rounds.filter { !$0.isActive }) { round in
                    NavigationLink(value: round.id) {
                        RoundRow(round: round)
                    }
                    .swipeActions(edge: .trailing) {
                        // Not role: .destructive — that would animate the row away before the alert confirms.
                        Button {
                            roundToDelete = round
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading) {
                        if roundStore.activeRound == nil {
                            Button {
                                roundStore.reactivateRound(round.id)
                                navigationPath.append(round.id)
                            } label: {
                                Label("Resume", systemImage: "play.fill")
                            }
                            .tint(.green)
                        }
                        Button {
                            exportRound(round)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("SpotGolf")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    Image(systemName: syncService.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                        .foregroundStyle(syncService.isConnected ? .green : .secondary)
                        .imageScale(.small)
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .imageScale(.small)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if roundStore.activeRound != nil {
                    Button("End Round") {
                        roundStore.endRound()
                    }
                } else {
                    Button("New Round") {
                        showCourseSelection = true
                    }
                    .disabled(!canStartRound)
                }
            }
        }
        .alert("Delete Round", isPresented: Binding(
            get: { roundToDelete != nil },
            set: { if !$0 { roundToDelete = nil } }
        ), presenting: roundToDelete) { round in
            Button("Delete", role: .destructive) {
                roundStore.deleteRound(round)
                trackStore.deleteRound(round.id)
                guessStore.deleteRound(round.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { round in
            Text("Delete \"\(round.displayTitle)\"? This cannot be undone.")
        }
        .alert("Sync Error", isPresented: Binding(
            get: { syncService.syncError != nil },
            set: { if !$0 { syncService.syncError = nil } }
        )) {
            Button("OK") { syncService.syncError = nil }
        } message: {
            Text(syncService.syncError ?? "")
        }
        .sheet(isPresented: $showCourseSelection) {
            CourseSelectionView(onRoundStarted: { roundID in
                navigationPath.append(roundID)
            })
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $export) { export in
            ShareSheet(items: [export.url])
                .presentationDetents([.medium, .large])
        }
    }

    /// The watch records all GPS, so a round can only start while it is connected.
    /// UI tests run without a paired watch, so they are exempt.
    private var canStartRound: Bool {
        CommandLine.arguments.contains("--ui-testing") || syncService.isConnected
    }

    /// Writes the round's GPS track to a temporary CSV file and opens the share panel.
    private func exportRound(_ round: Round) {
        let csv = TrackExporter.csv(round: round,
                                    phone: trackStore.points(for: round.id, source: .phone),
                                    watch: trackStore.points(for: round.id, source: .watch))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(TrackExporter.fileName(for: round))
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            export = RoundExport(url: url)
        } catch {
            print("Failed to write track export: \(error)")
        }
    }
}

private struct RoundExport: Identifiable {
    let id = UUID()
    let url: URL
}

/// The standard iOS share panel.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct RoundRow: View {
    let round: Round

    private var title: String { round.displayTitle }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("\(round.holes.count) hole\(round.holes.count == 1 ? "" : "s") · \(round.allMarks.count) mark\(round.allMarks.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if round.isActive {
                Text("Active")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
    }
}
