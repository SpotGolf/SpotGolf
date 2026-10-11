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

    /// The average distance an amateur hits the club, in yards. Nil for the putter only.
    var defaultDistance: Int? {
        Self.defaultDistances[id]
    }

    private static let defaultDistances: [String: Int] = [
        "dr": 230, "2w": 220, "3w": 215, "4w": 205, "5w": 200, "6w": 190, "7w": 185, "8w": 175, "9w": 170,
        "2h": 200, "3h": 190, "4h": 180, "5h": 170, "6h": 160, "7h": 150,
        "1i": 205, "2i": 195, "3i": 185, "4i": 175, "5i": 165, "6i": 155, "7i": 145, "8i": 135, "9i": 125,
        "pw": 115, "aw": 105, "sw": 90, "lw": 75,
        "46": 115, "48": 110, "50": 105, "52": 100, "54": 95, "56": 90, "58": 85, "60": 75, "62": 65, "64": 55,
    ]

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

/// The clubs the player carries, at most `capacity`, always in `Club.all` order, each with the
/// distance the player hits it. `GolfBagStore` saves the bag and changes it; see
/// plans/2026-10-10-club-distances.md.
struct GolfBag: Equatable, Sendable {
    /// The most clubs the rules allow.
    static let capacity = 14

    /// The standard 14, each at its default distance.
    static let standard = GolfBag(ids: ["dr", "3w", "5w", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "pw", "sw", "lw", "pu"])

    private(set) var clubs: [Club]
    private var yards: [Club: Int]

    /// One of each club, in bag order. A club missing from `distances` is at its default.
    init(clubs: [Club], distances: [Club: Int] = [:]) {
        let carried = Set(clubs)
        self.clubs = Club.all.filter { carried.contains($0) }
        yards = [:]
        for club in self.clubs {
            if let distance = distances[club] ?? club.defaultDistance {
                yards[club] = distance
            }
        }
    }

    /// IDs that are not clubs are dropped.
    init(ids: [String]) {
        self.init(clubs: ids.compactMap { Club.named($0) })
    }

    var isFull: Bool {
        clubs.count >= Self.capacity
    }

    func contains(_ club: Club) -> Bool {
        clubs.contains(club)
    }

    /// How far the player hits the club, in yards. Nil for the putter and for clubs not in the bag.
    func distance(of club: Club) -> Int? {
        yards[club]
    }
}
