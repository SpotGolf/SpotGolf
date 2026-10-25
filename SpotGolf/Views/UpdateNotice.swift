import SwiftUI

/// Tells the player that iCloud has rounds or settings saved by a newer version of the app,
/// which this one can't read. See plans/2026-10-22-cloudkit-sync.md.
enum UpdateNotice {
    static var title: LocalizedStringKey { "Update SpotGolf" }
    static var message: LocalizedStringKey { "Your settings or rounds in iCloud were saved by a newer version of SpotGolf. Update the app to keep them in sync on this iPhone." }
}

/// The notice at the top of Settings, while the app needs an update.
struct UpdateNoticeSection: View {
    @Environment(PhoneServices.self) private var services
    @Environment(\.openURL) private var openURL

    var body: some View {
        if services.cloudSync.needsAppUpdate {
            Section {
                Text(UpdateNotice.message)
                    .accessibilityIdentifier("UpdateNoticeMessage")
                if let url = AppStoreLink.url {
                    Button("Open App Store") { openURL(url) }
                }
            } header: {
                Text(UpdateNotice.title)
            }
        }
    }
}

/// The notice as an alert, once per launch, and never during a round so it does not cover the
/// map on the course.
struct UpdateNoticeAlert: ViewModifier {
    @Environment(PhoneServices.self) private var services
    @Environment(\.openURL) private var openURL
    @State private var isShown = false

    private var isDue: Bool {
        services.cloudSync.needsAppUpdate && !services.cloudSync.hasShownUpdateNotice
            && services.roundStore.currentRound == nil
    }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: showIfDue)
            .onChange(of: isDue) { showIfDue() }
            .alert(UpdateNotice.title, isPresented: $isShown) {
                if let url = AppStoreLink.url {
                    Button("Open App Store") { openURL(url) }
                    Button("Not Now", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                Text(UpdateNotice.message)
            }
    }

    private func showIfDue() {
        guard isDue else { return }
        services.cloudSync.hasShownUpdateNotice = true
        isShown = true
    }
}
