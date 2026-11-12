import SwiftUI

/// The Caddie's stats for the shot on the map: its club, the chance of each outcome, how far 95%
/// of shots spread, and whose scores the pattern comes from. See
/// plans/2026-11-11-shot-dispersion.md, section 6.
struct CaddieStatsSheet: View {
    let stats: CaddieStats?
    @Binding var skill: MissAngle.Source

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let stats {
                    Section {
                        row("Club", value: String(localized: "\(stats.club.name), \(stats.yards) yards"), identifier: "CaddieStatsClub")
                    }
                    Section("Where shots stop") {
                        percentRow("Fairway or green", stats.outcomes.fairwayOrGreen, identifier: "CaddieStatsFairway")
                        percentRow("Rough", stats.outcomes.rough, identifier: "CaddieStatsRough")
                        percentRow("Sand", stats.outcomes.sand, identifier: "CaddieStatsSand")
                        percentRow("Water", stats.outcomes.water, identifier: "CaddieStatsWater")
                    }
                    if let lateral = stats.lateral, let downrange = stats.downrange {
                        Section {
                            row("Left to right", value: String(localized: "±\(lateral) yards"), identifier: "CaddieStatsLateral")
                            row("Short to long", value: String(localized: "\(downrange.lowerBound)–\(downrange.upperBound) yards"),
                                identifier: "CaddieStatsDownrange")
                        } header: {
                            Text("Spread")
                        } footer: {
                            Text("Where 95 of 100 shots stop.")
                        }
                    }
                }
                Section {
                    Picker("Skill", selection: $skill) {
                        ForEach(MissAngle.Source.allCases, id: \.self) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .accessibilityIdentifier("CaddieSkill")
                } footer: {
                    Text("The pattern comes from published shots of golfers with these scores. Low is 70 to 83, mid is 84 to 97 and high is 98 to 120.")
                }
            }
            .navigationTitle("Caddie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("CloseCaddieStats")
                }
            }
        }
    }

    private func percentRow(_ title: LocalizedStringKey, _ share: Double, identifier: String) -> some View {
        row(title, value: String(localized: "\(CaddieStats.percent(share))%"), identifier: identifier)
    }

    private func row(_ title: LocalizedStringKey, value: String, identifier: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

extension MissAngle.Source {
    var title: LocalizedStringKey {
        switch self {
        case .myScores: "My scores"
        case .low: "Low scores"
        case .mid: "Mid scores"
        case .high: "High scores"
        }
    }
}
