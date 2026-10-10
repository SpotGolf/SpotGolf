import Foundation

/// The app's SemVer version from its Info.plist, set by `MARKETING_VERSION` in project.yml.
enum AppVersion {
    /// "0.1.0"
    static func text(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        info?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
