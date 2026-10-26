import SwiftUI

/// How far the player hits each club in the bag, in yards. The putter has no distance, so it is
/// left out. A field empties when it gets focus, with the saved distance as its placeholder, so
/// typing replaces the distance. A distance is saved when its field loses focus and when the
/// screen closes, not on every key, so iCloud gets one change per edit. See
/// plans/2026-10-26-edit-club-distances.md.
struct ClubDistancesView: View {
    @Environment(PhoneServices.self) private var services
    /// What each field shows while it is being edited, keyed by `Club.id`.
    @State private var drafts: [String: String] = [:]
    @FocusState private var focused: Club?

    /// The longest distance a field takes, in yards.
    static let maximum = 400

    private var clubs: [Club] {
        services.golfBag.bag.clubs.filter { $0.kind != .putter }
    }

    var body: some View {
        Form {
            Section {
                ForEach(clubs) { club in
                    LabeledContent(club.name) {
                        HStack(spacing: 4) {
                            TextField(placeholder(for: club), text: text(for: club))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focused, equals: club)
                                .frame(width: 56)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
                                .accessibilityIdentifier("Distance-\(club.id)")
                            Text("yd")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("How far you hit each club, in yards, from 1 to \(Self.maximum).")
            }
        }
        .navigationTitle("Club Distances")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focused != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { focused = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: focused) { old, new in
            if let old {
                commit(old)
            }
            if let new {
                drafts[new.id] = ""
            }
        }
        .onDisappear {
            for club in clubs {
                commit(club)
            }
        }
    }

    private func placeholder(for club: Club) -> String {
        services.golfBag.bag.distance(of: club).map(String.init) ?? ""
    }

    private func text(for club: Club) -> Binding<String> {
        Binding {
            drafts[club.id] ?? placeholder(for: club)
        } set: {
            drafts[club.id] = $0.filter(\.isNumber)
        }
    }

    /// Saves the club's draft when it is a distance in range. Otherwise the field goes back to
    /// the saved distance.
    private func commit(_ club: Club) {
        guard let draft = drafts.removeValue(forKey: club.id) else { return }
        guard let yards = Int(draft), (1...Self.maximum).contains(yards),
              yards != services.golfBag.bag.distance(of: club) else { return }
        services.golfBag.setDistance(yards, for: club)
    }
}
