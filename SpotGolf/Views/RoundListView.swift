import SwiftUI

struct RoundListView: View {
    @Binding var navigationPath: NavigationPath
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var syncService: SyncService
    @State private var showCourseSelection = false
    @State private var showSettings = false

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
                        Button(role: .destructive) {
                            roundStore.deleteRound(round)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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
                }
            }
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
    }
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
