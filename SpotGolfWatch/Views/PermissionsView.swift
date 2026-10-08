import SwiftUI

/// Shown in place of the round screen until every permission is granted. Location, motion
/// and health are shared with the iPhone app and can only be granted there; the microphone
/// is the watch's own, with its prompt here.
struct PermissionsView: View {
    @Environment(PermissionChecker.self) private var permissions
    @State private var isAsking = false

    private var phonePermissions: [AppPermission] { permissions.required.filter { !$0.isAskedOnWatch } }
    private var watchPermissions: [AppPermission] { permissions.required.filter(\.isAskedOnWatch) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if phonePermissions.contains(where: { permissions.states[$0] != .granted }) {
                    Text("Open SpotGolf on your iPhone to allow:")
                        .font(.headline)
                        .accessibilityIdentifier("OpenOnIPhone")
                } else {
                    Text("Allow on this watch:")
                        .font(.headline)
                }

                ForEach(phonePermissions, id: \.self) { permission in
                    row(permission)
                }

                ForEach(watchPermissions, id: \.self) { permission in
                    row(permission)
                    watchAction(permission)
                }
            }
            .padding()
        }
    }

    private func row(_ permission: AppPermission) -> some View {
        let granted = permissions.states[permission] == .granted
        return HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(permission.title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Permission_\(permission.rawValue)")
    }

    /// The prompt, or where to turn it on once it has been refused.
    @ViewBuilder
    private func watchAction(_ permission: AppPermission) -> some View {
        switch permissions.states[permission] {
        case .notAsked:
            Button("Allow \(permission.title)") {
                isAsking = true
                Task {
                    await permissions.requestMissing()
                    isAsking = false
                }
            }
            .disabled(isAsking)
            .accessibilityIdentifier("Allow_\(permission.rawValue)")
        case .denied:
            Text("Turn on \(permission.title) for SpotGolf in the watch's Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}
