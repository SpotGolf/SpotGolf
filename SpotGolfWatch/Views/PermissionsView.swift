import SwiftUI

/// Shown in place of the round screen until every permission is granted. The permissions are
/// shared with the iPhone app and can only be granted there.
struct PermissionsView: View {
    @EnvironmentObject var permissions: PermissionChecker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Open SpotGolf on your iPhone to allow:")
                    .font(.headline)
                    .accessibilityIdentifier("OpenOnIPhone")

                ForEach(permissions.required, id: \.self) { permission in
                    row(permission)
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
}
