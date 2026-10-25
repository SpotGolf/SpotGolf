import Foundation

/// The app's page in the App Store, for the update notice.
enum AppStoreLink {
    /// Nil until the app is published. Then `https://apps.apple.com/app/id<app id>`, with the ID
    /// App Store Connect gives the app.
    static let url: URL? = nil
}
