import Foundation
import Observation
import SwiftData

/// Saves the golf bag with SwiftData, one `CarriedClub` per club, and gives views the `GolfBag`
/// to show. See plans/2026-10-10-club-distances.md.
@MainActor
@Observable
final class GolfBagStore {
    /// The `UserDefaults` flag set once the standard bag has been put in the store.
    nonisolated static let seededKey = "bagSeeded"

    @ObservationIgnored private let context: ModelContext

    /// The bag as saved. Read again after every change, so views redraw.
    private(set) var bag = GolfBag(clubs: [])

    /// Puts the standard bag in an empty store the first time it runs. `defaults` remembers that
    /// it has, so a bag the player emptied stays empty.
    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        if !defaults.bool(forKey: Self.seededKey) {
            if rows().isEmpty {
                for club in GolfBag.standard.clubs {
                    context.insert(CarriedClub(club))
                }
                save()
            }
            defaults.set(true, forKey: Self.seededKey)
        }
        reload()
    }

    /// Takes the club out when it is in the bag, and puts it in at its default distance
    /// otherwise. A full bag stays as it is.
    func toggle(_ club: Club) {
        if let row = row(for: club) {
            context.delete(row)
        } else if !bag.isFull {
            context.insert(CarriedClub(club))
        } else {
            return
        }
        save()
        reload()
    }

    /// Changes how far the player hits a club in the bag. The putter has no distance.
    func setDistance(_ yards: Int, for club: Club) {
        guard club.kind != .putter, let row = row(for: club) else { return }
        row.distance = yards
        save()
        reload()
    }

    private func rows() -> [CarriedClub] {
        do {
            return try context.fetch(FetchDescriptor<CarriedClub>())
        } catch {
            Log.storage.error("Could not read the golf bag: \(String(describing: error))")
            return []
        }
    }

    private func row(for club: Club) -> CarriedClub? {
        let id = club.id
        var descriptor = FetchDescriptor<CarriedClub>(predicate: #Predicate { $0.clubID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Rows whose ID is not a club are left out.
    private func reload() {
        var clubs: [Club] = []
        var distances: [Club: Int] = [:]
        for row in rows() {
            guard let club = row.club else { continue }
            clubs.append(club)
            if let distance = row.distance {
                distances[club] = distance
            }
        }
        bag = GolfBag(clubs: clubs, distances: distances)
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Log.storage.error("Could not save the golf bag: \(String(describing: error))")
        }
    }
}
