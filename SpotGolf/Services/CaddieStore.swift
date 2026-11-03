import Foundation
import Observation

/// How far the player hits each club in the bag, for the Caddie screen and club guesses. The
/// shots are listed again only when an ended round changes or the Green Zone setting does; the
/// bag's distances, which each club starts from, are read as they are. See
/// plans/2026-11-02-caddie-club-distances.md, section 3.
@MainActor
@Observable
final class CaddieStore {
    /// Each club's counted shots, in yards.
    private(set) var shots: [Club: [Double]] = [:]

    @ObservationIgnored private let rounds: RoundStore
    @ObservationIgnored private let golfBag: GolfBagStore
    @ObservationIgnored private let defaults: UserDefaults
    /// What `shots` was listed from, so changes to anything else don't list them again.
    @ObservationIgnored private var listedFrom: Source?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    /// The ended rounds as they were, and the Green Zone setting.
    private struct Source: Equatable {
        var rounds: [RoundVersion]
        var greenZone: Double
    }

    private struct RoundVersion: Equatable {
        var id: UUID
        var changedAt: Date
        var strokesVersion: Int
    }

    init(rounds: RoundStore, golfBag: GolfBagStore, defaults: UserDefaults = .standard) {
        self.rounds = rounds
        self.golfBag = golfBag
        self.defaults = defaults
        listShots()
        rounds.addListener { [weak self] event in
            if case .roundsChanged = event {
                self?.listShots()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: nil) { [weak self] _ in
            // Posted on the thread that changed the setting: the app's own changes come on the main thread
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.listShots()
                }
            } else {
                Task { @MainActor in
                    self?.listShots()
                }
            }
        }
    }

    /// The club's distances. Nil for the putter and for clubs out of the bag.
    func distance(of club: Club) -> ClubDistance? {
        guard club.kind != .putter, let start = golfBag.bag.distance(of: club) else { return nil }
        return ClubDistance(startingDistance: start, shots: shots[club] ?? [])
    }

    /// Each club in the bag but the putter, in bag order, with its distances.
    var distances: [(club: Club, distance: ClubDistance)] {
        golfBag.bag.clubs.compactMap { club in distance(of: club).map { (club, $0) } }
    }

    /// The bag with each club at its Caddie average, for club guesses.
    var guessBag: GolfBag {
        var averages: [Club: Int] = [:]
        for (club, distance) in distances {
            averages[club] = distance.average
        }
        return GolfBag(clubs: golfBag.bag.clubs, distances: averages)
    }

    /// Lists the shots again when an ended round or the Green Zone setting changed. A change to
    /// the round in progress changes nothing: its shots don't count yet.
    private func listShots() {
        let ended = rounds.rounds.filter { $0.status == .ended }
        let source = Source(rounds: ended.map { RoundVersion(id: $0.id, changedAt: $0.changedAt, strokesVersion: $0.strokesVersion) },
                            greenZone: defaults.double(forKey: SettingsKey.greenZone))
        guard source != listedFrom else { return }
        listedFrom = source
        shots = ShotDistances.shots(in: ended, greenZone: source.greenZone)
    }
}
