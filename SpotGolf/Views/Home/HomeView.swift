import SwiftUI

/// The home screen: the active tab's screen above the tab bar, with the watch status and End
/// Round in the navigation bar. Screens pushed from a tab, such as a round's map, cover the bar.
/// See plans/2026-11-02-caddie-club-distances.md, sections 1 and 2.
struct HomeView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(PhoneServices.self) private var services
    /// Rounds on every launch.
    @State private var tab = HomeTab.rounds
    /// The New Round tab's search, whose field is in the tab bar while the course list shows.
    @State private var courseSearch = ""
    @State private var showsCourseSearch = false
    @FocusState private var isSearching: Bool

    var body: some View {
        screen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeTabBar(selection: tab, hasRound: services.roundStore.currentRound != nil,
                           canStartRound: canStartRound, showsButtons: !isSearching, onSelect: select) {
                    if tab == .newRound && showsCourseSearch {
                        CourseSearchField(text: $courseSearch, isFocused: $isSearching)
                    }
                }
            }
            .toolbar {
                // A status, not a button, so it has no glass background of its own
                watchStatusItem
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    if tab == .rounds, let current = services.roundStore.currentRound, current.isActive {
                        Button("End Round") {
                            services.phoneSync.endRound(current.id)
                        }
                    }
                }
            }
            .modifier(UpdateNoticeAlert())
            .alert("Sync Error", isPresented: Binding(
                get: { services.syncService.syncError != nil },
                set: { if !$0 { services.syncService.syncError = nil } }
            )) {
                Button("OK") { services.syncService.syncError = nil }
            } message: {
                Text(services.syncService.syncError ?? "")
            }
            .onChange(of: tab) {
                courseSearch = ""
            }
            .onChange(of: services.roundStore.currentRound?.id) { _, roundID in
                // The new round questions are only for when no round is in progress
                if roundID != nil && tab == .newRound {
                    tab = .rounds
                }
            }
    }

    @ViewBuilder
    private var screen: some View {
        switch tab {
        case .rounds:
            RoundListView(navigationPath: $navigationPath)
        case .caddie:
            CaddieView()
        case .newRound:
            CourseSelectionView(isTab: true, tabSearchText: $courseSearch, showsCourseList: $showsCourseSearch,
                                onRoundStarted: { roundID in
                                    // Back from the map shows the round at the top of the list
                                    tab = .rounds
                                    navigationPath.append(roundID)
                                })
        case .puttSharing:
            PuttDataSharingView()
        case .settings:
            SettingsView()
        }
    }

    /// The + opens the round in progress, without changing the tab, and the new round questions
    /// otherwise.
    private func select(_ selected: HomeTab) {
        if selected == .newRound, let current = services.roundStore.currentRound {
            navigationPath.append(current.id)
            return
        }
        tab = selected
    }

    /// Whether the watch is connected.
    private var watchStatusItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Image(systemName: services.syncService.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                .foregroundStyle(services.syncService.isConnected ? .green : .secondary)
                .accessibilityLabel(services.syncService.isConnected ? "Watch connected" : "Watch not connected")
        }
    }

    /// The watch records all GPS, so a round needs a paired watch with the app installed.
    /// It does not need to be reachable: starting a round launches the watch app.
    /// UI tests run without a paired watch, so they are exempt.
    private var canStartRound: Bool {
        !services.requiresWatch || services.syncService.hasCounterpart
    }
}
