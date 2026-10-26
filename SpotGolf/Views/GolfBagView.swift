import SwiftUI

/// The clubs the player carries: a button per club, filled when it is in the bag. See
/// plans/2026-10-10-golf-bag.md.
struct GolfBagView: View {
    @Environment(PhoneServices.self) private var services

    private var bag: GolfBag { services.golfBag.bag }

    var body: some View {
        Form {
            Section {
                ForEach(ClubKind.allCases, id: \.self) { kind in
                    Section {
                        ClubGrid(clubs: Club.all.filter { $0.kind == kind },
                                 isSelected: { bag.contains($0) },
                                 isEnabled: { bag.contains($0) || !bag.isFull }) { club in
                            services.golfBag.toggle(club)
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                        .listRowSeparator(.hidden, edges: .bottom)
                    } header: {
                        Text(kind.title)
                    }
                }
            } header: {
                Text("\(bag.clubs.count) of \(GolfBag.capacity) clubs")
                    .accessibilityIdentifier("BagCount")
            } footer: {
                Text("Tap a club to add it to your bag or take it out. A bag holds at most \(GolfBag.capacity) clubs.")
            }
        }
        .navigationTitle("Golf Bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Distances") {
                    ClubDistancesView()
                }
                .accessibilityIdentifier("EditDistances")
            }
        }
    }
}
