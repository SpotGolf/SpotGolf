import SwiftUI

/// Shows a round that is waiting on the watch: starting (with Retry and Cancel) or ending
/// (with Force end). Shows nothing for an active or ended round.
struct RoundSyncBanner: View {
    let round: Round
    @EnvironmentObject var phoneSync: PhoneSync

    var body: some View {
        switch round.status {
        case .starting:
            if phoneSync.startStates[round.id] == .timedOut {
                banner("The watch did not respond.") {
                    Button("Retry") { phoneSync.retryStart(round.id) }
                        .accessibilityIdentifier("RetryStart")
                    Button("Cancel", role: .destructive) { phoneSync.cancelStart(round.id) }
                        .accessibilityIdentifier("CancelStart")
                }
            } else {
                banner("Starting on watch…", showsProgress: true) {
                    Button("Cancel", role: .destructive) { phoneSync.cancelStart(round.id) }
                        .accessibilityIdentifier("CancelStart")
                }
            }
        case .ending:
            banner("Syncing watch data…", showsProgress: true) {
                Button("Force end") { phoneSync.forceEnd(round.id) }
                    .accessibilityIdentifier("ForceEnd")
            }
        case .active, .ended:
            EmptyView()
        }
    }

    private func banner(_ text: String, showsProgress: Bool = false,
                        @ViewBuilder buttons: () -> some View) -> some View {
        HStack(spacing: 12) {
            if showsProgress {
                ProgressView()
            }
            Text(text)
                .font(.subheadline)
            Spacer()
            buttons()
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
