import SwiftUI

struct RoundListView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var syncService: SyncService
    @State private var showCourseSelection = false

    var body: some View {
        List {
            if let active = roundStore.activeRound {
                Section("Active Round") {
                    NavigationLink {
                        RoundMapView(roundID: active.id)
                    } label: {
                        RoundRow(round: active)
                    }
                }
            }

            Section("Past Rounds") {
                ForEach(roundStore.rounds.filter { !$0.isActive }) { round in
                    NavigationLink {
                        RoundMapView(roundID: round.id)
                    } label: {
                        RoundRow(round: round)
                    }
                }
                .onDelete { offsets in
                    let pastRounds = roundStore.rounds.filter { !$0.isActive }
                    for index in offsets {
                        roundStore.deleteRound(pastRounds[index])
                    }
                }
            }
        }
        .navigationTitle("SpotGolf")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image(systemName: syncService.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .foregroundStyle(syncService.isConnected ? .green : .secondary)
                    .imageScale(.small)
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
        .sheet(isPresented: $showCourseSelection) {
            CourseSelectionView()
        }
    }
}

private struct RoundRow: View {
    let round: Round

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(round.formattedDate)
                    .font(.headline)
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
