import SwiftUI

/// When each hole started. Estimated times can be wrong, so any start time can be set by hand.
struct HoleTimelineView: View {
    let roundID: UUID
    @EnvironmentObject var roundStore: RoundStore
    @Environment(\.dismiss) private var dismiss

    private var round: Round? {
        roundStore.round(roundID)
    }

    var body: some View {
        NavigationStack {
            List {
                if let round {
                    ForEach(round.holeTimeline) { entry in
                        row(entry, round: round)
                    }
                }
            }
            .navigationTitle("Hole Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ entry: HoleStart, round: Round) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hole \(entry.holeIndex + 1)")
                    .font(.headline)
                if let label = label(for: entry.source) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(entry.source == .estimated ? .orange : .secondary)
                }
            }
            Spacer()
            if entry.source == .roundStart {
                Text(entry.startedAt, style: .time)
                    .foregroundStyle(.secondary)
            } else {
                DatePicker("Start time", selection: Binding(
                    get: { entry.startedAt },
                    set: { roundStore.setStartTime($0, entryID: entry.id, roundID: round.id) }
                ), in: RoundStore.startTimeRange(for: entry.id, in: round.holeTimeline) ?? entry.startedAt...entry.startedAt,
                   displayedComponents: .hourAndMinute)
                .labelsHidden()
            }
        }
        .accessibilityIdentifier("HoleTime_\(entry.holeIndex + 1)")
    }

    private func label(for source: HoleStartSource) -> String? {
        switch source {
        case .roundStart: "Round start"
        case .autoAdvance: nil
        case .playHole: "Chosen"
        case .estimated: "Estimated"
        case .corrected: "Corrected"
        case .userSet: "Set by you"
        }
    }
}
