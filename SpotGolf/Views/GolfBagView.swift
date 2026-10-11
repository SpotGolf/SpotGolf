import SwiftUI

/// The clubs the player carries: a button per club, filled when it is in the bag. See
/// plans/2026-10-10-golf-bag.md.
struct GolfBagView: View {
    @AppStorage(SettingsKey.bag) private var bag = GolfBag.standard

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 8)]

    var body: some View {
        Form {
            Section {
                ForEach(ClubKind.allCases, id: \.self) { kind in
                    Section {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Club.all.filter { $0.kind == kind }) { club in
                                clubButton(club)
                            }
                        }
                        .padding(.vertical, 4)
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
    }

    @ViewBuilder
    private func clubButton(_ club: Club) -> some View {
        let carried = bag.contains(club)
        let button = Button {
            bag.toggle(club)
        } label: {
            Text(club.shortName)
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .disabled(!carried && bag.isFull)
        .accessibilityLabel(club.name)
        .accessibilityIdentifier("Club-\(club.id)")
        .accessibilityAddTraits(carried ? .isSelected : [])
        if carried {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered).tint(.gray)
        }
    }
}
