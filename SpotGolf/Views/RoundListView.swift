import SwiftData
import SwiftUI
import os

struct RoundListView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(PhoneServices.self) private var services
    @State private var showCourseSelection = false
    @State private var showSettings = false
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]
    /// Its ID and title, since the alert can still show while the deleted round goes away.
    @State private var roundToDelete: (id: UUID, title: String)?
    @State private var export: RoundExport?
    @State private var logRound: Round?

    var body: some View {
        List {
            if let current = services.roundStore.currentRound {
                Section("Active Round") {
                    NavigationLink(value: current.id) {
                        RoundRow(round: current)
                    }
                    if current.status != .active {
                        RoundSyncBanner(round: current)
                            .listRowInsets(EdgeInsets())
                    }
                }
            }

            Section("Past Rounds") {
                ForEach(rounds.filter { $0.status == .ended }) { round in
                    NavigationLink(value: round.id) {
                        RoundRow(round: round)
                    }
                    .swipeActions(edge: .trailing) {
                        // Not role: .destructive — that would animate the row away before the alert confirms.
                        Button {
                            roundToDelete = (round.id, round.displayTitle)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading) {
                        if services.roundStore.currentRound == nil && canStartRound {
                            Button {
                                services.phoneSync.resumeRound(round.id)
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
                        Button {
                            logRound = round
                        } label: {
                            Label("Log", systemImage: "doc.text")
                        }
                        .tint(.gray)
                    }
                }
            }
        }
        .navigationTitle("SpotGolf")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            if #available(iOS 26.0, *) {
                // A status, not a button, so it has no glass background of its own
                watchStatusItem
                    .sharedBackgroundVisibility(.hidden)
            } else {
                watchStatusItem
            }
            ToolbarItem(placement: .primaryAction) {
                if let current = services.roundStore.currentRound {
                    if current.isActive {
                        Button("End Round") {
                            services.phoneSync.endRound(current.id)
                        }
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
                services.roundStore.deleteRound(round.id)
                services.streamStore.delete(round.id)
                services.logStore.delete(round.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { round in
            Text("Delete \"\(round.title)\"? This cannot be undone.")
        }
        .alert("Sync Error", isPresented: Binding(
            get: { services.syncService.syncError != nil },
            set: { if !$0 { services.syncService.syncError = nil } }
        )) {
            Button("OK") { services.syncService.syncError = nil }
        } message: {
            Text(services.syncService.syncError ?? "")
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
        .sheet(item: $logRound) { round in
            NavigationStack {
                LogView(scope: .round(round))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { logRound = nil }
                        }
                    }
            }
        }
    }

    /// The watch records all GPS, so a round needs a paired watch with the app installed.
    /// It does not need to be reachable: starting a round launches the watch app.
    /// UI tests run without a paired watch, so they are exempt.

    /// Whether the watch is connected.
    private var watchStatusItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Image(systemName: services.syncService.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                .foregroundStyle(services.syncService.isConnected ? .green : .secondary)
                .accessibilityLabel(services.syncService.isConnected ? "Watch connected" : "Watch not connected")
        }
    }
    private var canStartRound: Bool {
        !services.requiresWatch || services.syncService.hasCounterpart
    }

    /// Writes the round's GPS track to a temporary CSV file and opens the share panel.
    private func exportRound(_ round: Round) {
        let csv = TrackExporter.csv(round: round,
                                    points: services.streamStore.points(for: round.id, until: round.endedAt),
                                    swings: services.streamStore.swings(for: round.id, until: round.endedAt),
                                    contacts: services.streamStore.contacts(for: round.id, until: round.endedAt),
                                    events: services.streamStore.events(for: round.id, until: round.endedAt))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(TrackExporter.fileName(for: round))
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            export = RoundExport(url: url)
        } catch {
            Log.export.error("Could not write track export: \(String(describing: error))")
        }
    }
}

private struct RoundExport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RoundRow: View {
    let round: Round

    private var title: String { round.displayTitle }

    private var statusText: LocalizedStringKey? {
        switch round.status {
        case .starting: "Starting"
        case .active: "Active"
        case .ending: "Ending"
        case .ended: nil
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(verbatim: String(localized: "\(round.holes.count) holes") + " · " + String(localized: "\(round.allStrokes.count) strokes"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let status = statusText {
                Text(status)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
    }
}
