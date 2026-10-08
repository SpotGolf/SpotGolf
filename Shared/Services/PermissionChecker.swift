import Foundation
import Observation
import os

/// Reads and asks for permissions. Each app reads the system; tests and UI tests use fakes.
@MainActor
protocol PermissionSource: AnyObject {
    func state(of permission: AppPermission) -> PermissionState
    /// Shows the system prompt and returns once the user answers.
    func request(_ permission: AppPermission) async
    /// Calls `changed` whenever the system says a permission changed, such as an "Allow Once"
    /// location grant running out.
    func observe(_ changed: @escaping () -> Void)
}

extension PermissionSource {
    func observe(_ changed: @escaping () -> Void) {}
}

/// Says every permission is granted. UI tests use it, since simulators can't grant them all.
@MainActor
final class GrantedPermissionSource: PermissionSource {
    func state(of permission: AppPermission) -> PermissionState { .granted }
    func request(_ permission: AppPermission) async {}
}

/// Checks and asks for the permissions an app needs. The app does nothing else until all
/// are granted.
@MainActor
@Observable
final class PermissionChecker {
    private(set) var states: [AppPermission: PermissionState] = [:]

    /// The permissions this app needs, in the order they are asked for.
    let required: [AppPermission]

    private let source: PermissionSource

    init(source: PermissionSource, required: [AppPermission] = AppPermission.allCases) {
        self.source = source
        self.required = required
        refresh()
        source.observe { [weak self] in self?.refresh() }
    }

    /// Required permissions not granted, in `required` order.
    var missing: [AppPermission] {
        required.filter { states[$0] != .granted }
    }

    var allGranted: Bool { missing.isEmpty }

    /// Reads every required permission again.
    func refresh() {
        let states = Dictionary(uniqueKeysWithValues: required.map { ($0, source.state(of: $0)) })
        guard states != self.states else { return }
        self.states = states
        let summary = required.map { "\($0.rawValue)=\(states[$0] ?? .notAsked)" }.joined(separator: " ")
        if allGranted {
            Log.permissions.notice("Permissions: \(summary, privacy: .public)")
        } else {
            Log.permissions.error("Permissions missing: \(summary, privacy: .public)")
        }
    }

    /// Shows the prompt for each required permission not yet asked, one at a time. Denied
    /// ones can only be turned on in Settings.
    func requestMissing() async {
        for permission in required where source.state(of: permission) == .notAsked {
            Log.permissions.notice("Asking for \(permission.rawValue, privacy: .public)")
            await source.request(permission)
        }
        refresh()
    }
}
