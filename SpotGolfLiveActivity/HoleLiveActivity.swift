import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SpotGolfLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        HoleLiveActivity()
    }
}

/// The current hole on the Lock Screen and in the Dynamic Island.
struct HoleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HoleActivityAttributes.self) { context in
            LockScreenView(courseName: context.attributes.courseName, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hole \(state.holeNumber)")
                            .font(.headline)
                        if let par = state.par {
                            Text("Par \(par)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(yardsText(state))
                            .font(.headline)
                            .monospacedDigit()
                        Text("to center")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        Text(previousText(state))
                            .font(.subheadline)
                        Text(scoreText(state))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text("H\(state.holeNumber)")
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(yardsText(state))
                    .monospacedDigit()
            } minimal: {
                Text("\(state.holeNumber)")
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct LockScreenView: View {
    let courseName: String
    let state: HoleActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(state.holeNumber)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.green))

            VStack(alignment: .leading, spacing: 2) {
                Text(courseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(state.par.map { "Par \($0)" } ?? "Hole \(state.holeNumber)")
                    .font(.headline)
                Text(previousText(state))
                    .font(.subheadline)
                Text(scoreText(state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text(yardsText(state))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                Text("yds to center")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

/// The yards to the green, or a dash when they are not known.
private func yardsText(_ state: HoleActivityAttributes.ContentState) -> String {
    state.yardsToGreen.map(String.init) ?? "—"
}

/// "Previous 152 yds"
private func previousText(_ state: HoleActivityAttributes.ContentState) -> String {
    "Previous \(state.previousYards) yds"
}

/// "This hole 2 · Total 37 (+3)"
private func scoreText(_ state: HoleActivityAttributes.ContentState) -> String {
    let toPar = state.toPar.map { $0 == 0 ? " (E)" : $0 > 0 ? " (+\($0))" : " (\($0))" } ?? ""
    return "This hole \(state.holeStrokes) · Total \(state.totalStrokes)\(toPar)"
}
