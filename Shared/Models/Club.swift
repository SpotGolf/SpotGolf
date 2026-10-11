import Foundation

/// The kinds of club, in bag order. See plans/2026-10-10-golf-bag.md.
enum ClubKind: String, CaseIterable, Sendable {
    case wood, hybrid, iron, wedge, putter

    var title: String {
        switch self {
        case .wood: String(localized: "Woods")
        case .hybrid: String(localized: "Hybrids")
        case .iron: String(localized: "Irons")
        case .wedge: String(localized: "Wedges")
        case .putter: String(localized: "Putter")
        }
    }
}

/// A club a player can carry.
struct Club: Hashable, Identifiable, Sendable {
    /// Saved in settings, so it never changes: `dr`, `3w`, `4h`, `7i`, `pw`, `52`, `pu`.
    let id: String
    let kind: ClubKind
    /// What the bag's buttons show: `Dr`, `3w`, `7i`, `PW`, `52°`, `Pu`.
    let shortName: String
    let name: String

    /// Every club a player can carry, in bag order.
    static let all: [Club] = {
        var clubs = [Club(id: "dr", kind: .wood, shortName: "Dr", name: String(localized: "Driver"))]
        clubs += (2...9).map { Club(id: "\($0)w", kind: .wood, shortName: "\($0)w", name: String(localized: "\($0) Wood")) }
        clubs += (2...7).map { Club(id: "\($0)h", kind: .hybrid, shortName: "\($0)h", name: String(localized: "\($0) Hybrid")) }
        clubs += (1...9).map { Club(id: "\($0)i", kind: .iron, shortName: "\($0)i", name: String(localized: "\($0) Iron")) }
        clubs += [
            Club(id: "pw", kind: .wedge, shortName: "PW", name: String(localized: "Pitching Wedge")),
            Club(id: "aw", kind: .wedge, shortName: "AW", name: String(localized: "Approach Wedge")),
            Club(id: "sw", kind: .wedge, shortName: "SW", name: String(localized: "Sand Wedge")),
            Club(id: "lw", kind: .wedge, shortName: "LW", name: String(localized: "Lob Wedge")),
        ]
        clubs += stride(from: 46, through: 64, by: 2).map {
            Club(id: "\($0)", kind: .wedge, shortName: "\($0)°", name: String(localized: "\($0)° Wedge"))
        }
        clubs.append(Club(id: "pu", kind: .putter, shortName: "Pu", name: String(localized: "Putter")))
        return clubs
    }()

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func named(_ id: String) -> Club? {
        byID[id]
    }
}

/// The clubs the player carries, at most `capacity`, always in `Club.all` order. Saved in
/// settings as the club IDs joined by commas.
struct GolfBag: Equatable, RawRepresentable, Sendable {
    /// The most clubs the rules allow.
    static let capacity = 14

    static let standard = GolfBag(ids: ["dr", "3w", "5w", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "pw", "sw", "lw", "pu"])

    private(set) var clubs: [Club]

    init(clubs: [Club]) {
        let carried = Set(clubs)
        self.clubs = Club.all.filter { carried.contains($0) }
    }

    /// IDs that are not clubs are dropped.
    init(ids: [String]) {
        self.init(clubs: ids.compactMap { Club.named($0) })
    }

    init?(rawValue: String) {
        self.init(ids: rawValue.split(separator: ",").map(String.init))
    }

    var rawValue: String {
        clubs.map(\.id).joined(separator: ",")
    }

    var isFull: Bool {
        clubs.count >= Self.capacity
    }

    func contains(_ club: Club) -> Bool {
        clubs.contains(club)
    }

    /// Removes the club when it is in the bag, and adds it otherwise. A full bag stays as it is.
    mutating func toggle(_ club: Club) {
        if contains(club) {
            clubs.removeAll { $0 == club }
        } else if !isFull {
            self = GolfBag(clubs: clubs + [club])
        }
    }
}
