import CoreLocation
import SwiftData
import XCTest
@testable import SpotGolf

/// The Caddie's distances and the bag club guesses use, kept current as rounds, the bag and the
/// Green Zone setting change. See plans/2026-11-02-caddie-club-distances.md, section 3.
@MainActor
final class CaddieStoreTests: XCTestCase {
    private static let suiteName = "CaddieStoreTests"

    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private var rounds: RoundStore!
    private var golfBag: GolfBagStore!
    private var caddie: CaddieStore!

    private let driver = Club.named("dr")!
    private let lobWedge = Club.named("lw")!
    private let putter = Club.named("pu")!

    override func setUp() async throws {
        try await super.setUp()
        container = Storage.inMemoryContainer()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults.set(10.0, forKey: SettingsKey.greenZone)
        rounds = RoundStore(context: container.mainContext)
        golfBag = GolfBagStore(context: container.mainContext, defaults: defaults)
        caddie = CaddieStore(rounds: rounds, golfBag: golfBag, defaults: defaults)
    }

    override func tearDown() async throws {
        caddie = nil
        golfBag = nil
        rounds = nil
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        container = nil
        try await super.tearDown()
    }

    private func stroke(north: Double, club: Club?) -> Stroke {
        let coordinate = PathCourse.coordinate(north: north, east: 0)
        return Stroke(coordinate: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon), club: club)
    }

    /// A round on `PathCourse` with a 200 m drive and a lob wedge from 15 m short of the green's
    /// edge, ended unless `ended` is false.
    @discardableResult
    private func playRound(ended: Bool = true) -> Round {
        let round = rounds.startRound(courseSelection: PathCourse.selection)
        for spot in [stroke(north: 0, club: driver), stroke(north: 200, club: driver),
                     stroke(north: 270, club: lobWedge), stroke(north: 300, club: putter)] {
            rounds.addStroke(to: round.id, holeIndex: 0, stroke: spot)
        }
        if ended {
            rounds.update(round.id) { $0.end(at: Date()) }
        }
        return round
    }

    func testClubsStartAtTheirBagDistances() {
        XCTAssertEqual(caddie.guessBag, golfBag.bag, "With no shots, guesses use the bag's distances")
        XCTAssertNil(caddie.guessBag.distance(of: putter))
        XCTAssertEqual(caddie.distance(of: driver), ClubDistance(startingDistance: 230, shots: []))
    }

    func testDistancesFollowTheBagWithoutThePutter() {
        XCTAssertEqual(caddie.distances.map(\.club), golfBag.bag.clubs.filter { $0 != putter })

        golfBag.toggle(lobWedge)

        XCTAssertFalse(caddie.distances.map(\.club).contains(lobWedge), "A club out of the bag is not shown")
        XCTAssertNil(caddie.distance(of: lobWedge))
    }

    func testAnEndedRoundMovesTheAverages() throws {
        playRound()

        let drive = try XCTUnwrap(caddie.distance(of: driver))
        XCTAssertEqual(drive.shots, 2, "The drive and the second shot with the driver")
        XCTAssertNotEqual(drive.average, 230)
        XCTAssertEqual(caddie.guessBag.distance(of: driver), drive.average, "Guesses use the Caddie average")
    }

    func testARoundInProgressChangesNothingUntilItEnds() {
        let round = playRound(ended: false)
        XCTAssertEqual(caddie.distance(of: driver)?.shots, 0, "Its shots don't count yet")

        rounds.update(round.id) { $0.end(at: Date()) }

        XCTAssertEqual(caddie.distance(of: driver)?.shots, 2)
    }

    func testEditingAndDeletingAPastRoundChangeTheShots() throws {
        let round = playRound()
        let drive = try XCTUnwrap(round.holes[0].strokes.first)

        rounds.setShotQuality(.bad, strokeID: drive.id, in: round.id)
        XCTAssertEqual(caddie.distance(of: driver)?.shots, 1, "A thumbs-down shot is left out")

        rounds.deleteRound(round.id)
        XCTAssertEqual(caddie.distance(of: driver)?.shots, 0)
    }

    func testABagDistanceChangeMovesTheStart() {
        golfBag.setDistance(250, for: driver)

        XCTAssertEqual(caddie.distance(of: driver)?.average, 250)
        XCTAssertEqual(caddie.guessBag.distance(of: driver), 250)
    }

    func testTheGreenZoneSettingDecidesWhichShotsCount() {
        playRound()
        XCTAssertEqual(caddie.distance(of: lobWedge)?.shots, 1, "15 m from the edge is outside a 10 m zone")

        defaults.set(20.0, forKey: SettingsKey.greenZone)

        XCTAssertEqual(caddie.distance(of: lobWedge)?.shots, 0, "and inside a 20 m one")
    }
}
