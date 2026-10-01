import SwiftUI

/// Shown in place of the app until every required permission is granted. Allow shows the
/// prompt for each one not yet asked; a denied one can only be turned on in Settings.
struct PhonePermissionsView: View {
    @EnvironmentObject var permissions: PermissionChecker
    @Environment(\.openURL) private var openURL
    @State private var isAsking = false

    private var hasNotAsked: Bool {
        permissions.missing.contains { permissions.states[$0] == .notAsked }
    }

    private var hasDenied: Bool {
        permissions.missing.contains { permissions.states[$0] == .denied }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("SpotGolf needs these to record your round")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(permissions.required, id: \.self) { permission in
                        row(permission)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        // At the bottom, full width, like the system's own permission screens
        .safeAreaInset(edge: .bottom) {
            actionButton
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if hasNotAsked {
            Button {
                isAsking = true
                Task {
                    await permissions.requestMissing()
                    isAsking = false
                }
            } label: {
                Text("Allow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAsking)
            .accessibilityIdentifier("AllowPermissions")
        } else if hasDenied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("Open Settings")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("OpenSettings")
        }
    }

    private func row(_ permission: AppPermission) -> some View {
        let state = permissions.states[permission] ?? .notAsked
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(state == .granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(permission.title)
                    .font(.body.weight(.medium))
                if state == .denied {
                    Text(Self.howToTurnOn(permission))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Permission_\(permission.rawValue)")
    }

    /// What to set on SpotGolf's page in Settings.
    private static func howToTurnOn(_ permission: AppPermission) -> String {
        switch permission {
        case .location:
            "In Settings, set Location to While Using the App and turn on Precise Location."
        case .motion:
            "In Settings, turn on Motion & Fitness. If it is greyed out, turn on Fitness Tracking in Settings → Privacy & Security → Motion & Fitness."
        case .health:
            "In Settings → Privacy & Security → Health → SpotGolf, turn on Workouts."
        }
    }
}
