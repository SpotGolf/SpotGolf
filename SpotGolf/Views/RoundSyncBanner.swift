import SwiftUI

/// Shows a round that is waiting on the watch: starting (with Retry and Cancel after a timeout
/// or a refusal for missing permissions) or ending (with Force end). Shows nothing for an
/// active or ended round.
struct RoundSyncBanner: View {
    let round: Round
    @Environment(PhoneServices.self) private var services
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch round.status {
        case .starting:
            if case .needsPermissions(let missing) = services.phoneSync.startStates[round.id] {
                // The watch shares the phone's permissions, so they are changed in Settings here;
                // the microphone is granted on the watch, where Settings here cannot reach
                banner(Text(missingText(missing))) {
                    if missing.contains(where: { !$0.isAskedOnWatch }) {
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .accessibilityIdentifier("OpenSettings")
                    }
                    Button("Retry") { services.phoneSync.retryStart(round.id) }
                        .accessibilityIdentifier("RetryStart")
                    Button("Cancel", role: .destructive) { services.phoneSync.cancelStart(round.id) }
                        .accessibilityIdentifier("CancelStart")
                }
            } else if services.phoneSync.startStates[round.id] == .timedOut {
                banner(Text("The watch did not respond.")) {
                    Button("Retry") { services.phoneSync.retryStart(round.id) }
                        .accessibilityIdentifier("RetryStart")
                    Button("Cancel", role: .destructive) { services.phoneSync.cancelStart(round.id) }
                        .accessibilityIdentifier("CancelStart")
                }
            } else {
                banner(Text("Starting on watch…"), showsProgress: true) {
                    Button("Cancel", role: .destructive) { services.phoneSync.cancelStart(round.id) }
                        .accessibilityIdentifier("CancelStart")
                }
            }
        case .ending:
            banner(Text("Syncing watch data…"), showsProgress: true) {
                Button("Force end") { services.phoneSync.forceEnd(round.id) }
                    .accessibilityIdentifier("ForceEnd")
            }
        case .active, .ended:
            EmptyView()
        }
    }

    private func banner(_ text: Text, showsProgress: Bool = false,
                        @ViewBuilder buttons: () -> some View) -> some View {
        HStack(spacing: 12) {
            if showsProgress {
                ProgressView()
            }
            text
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

    /// Where each missing permission is granted: the microphone on the watch, the rest here.
    private func missingText(_ missing: [AppPermission]) -> String {
        let onWatch = missing.filter(\.isAskedOnWatch)
        let onPhone = missing.filter { !$0.isAskedOnWatch }
        var parts: [String] = []
        if !onPhone.isEmpty {
            let names = onPhone.map(\.title).formatted(.list(type: .and))
            parts.append(String(localized: "The watch is missing \(names) permission."))
        }
        if !onWatch.isEmpty {
            let names = onWatch.map(\.title).formatted(.list(type: .and))
            parts.append(String(localized: "Open SpotGolf on the watch and allow the \(names)."))
        }
        return parts.joined(separator: " ")
    }
}
