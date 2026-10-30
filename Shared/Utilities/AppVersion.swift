import Foundation

/// The app's SemVer version from its Info.plist, set by `MARKETING_VERSION` in project.yml.
enum AppVersion {
    /// "0.1.0"
    static func text(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        info?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// When the app was built, in ISO 8601 UTC ("2026-10-29T23:10:05Z"). A build script in
    /// project.yml sets it on every build.
    static func buildInstant(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        info?["SpotGolfBuildInstant"] as? String ?? "?"
    }
}
