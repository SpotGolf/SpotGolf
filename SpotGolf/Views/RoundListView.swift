import SwiftUI

struct RoundListView: View {
    @EnvironmentObject var roundStore: RoundStore

    var body: some View {
        List {
            if let active = roundStore.activeRound {
                Section("Active Round") {
                    NavigationLink {
                        RoundMapView(round: active)
                    } label: {
                        RoundRow(round: active)
                    }
                }
            }

            Section("Past Rounds") {
                ForEach(roundStore.rounds.filter { !$0.isActive }) { round in
                    NavigationLink {
                        RoundMapView(round: round)
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
            ToolbarItem(placement: .primaryAction) {
                if roundStore.activeRound != nil {
                    Button("End Round") {
                        roundStore.endRound()
                    }
                } else {
                    Button("New Round") {
                        roundStore.startRound()
                    }
                }
            }
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
                Text("\(round.marks.count) mark\(round.marks.count == 1 ? "" : "s")")
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
