import SwiftUI

struct ContentView: View {
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            RoundListView(navigationPath: $navigationPath)
                .navigationDestination(for: UUID.self) { roundID in
                    RoundMapView(roundID: roundID)
                }
        }
    }
}
