import SwiftData
import XCTest
@testable import SpotGolf

@MainActor
final class GolfBagStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private var store: GolfBagStore!

    private let driver = Club.named("dr")!
    private let twoWood = Club.named("2w")!
    private let fiveWood = Club.named("5w")!
    private let fourHybrid = Club.named("4h")!
    private let putter = Club.named("pu")!

    override func setUp() async throws {
        try await super.setUp()
        container = Storage.inMemoryContainer()
        defaults = UserDefaults(suiteName: "GolfBagStoreTests")
        defaults.removePersistentDomain(forName: "GolfBagStoreTests")
        store = GolfBagStore(context: container.mainContext, defaults: defaults)
    }

    override func tearDown() async throws {
        store = nil
        defaults.removePersistentDomain(forName: "GolfBagStoreTests")
        defaults = nil
        container = nil
        try await super.tearDown()
    }

    /// A store opened again on the same saved data, as at the next launch.
    private func reopened() -> GolfBagStore {
        GolfBagStore(context: container.mainContext, defaults: defaults)
    }

    func testNewStoreHoldsTheStandardBagAtDefaultDistances() {
        XCTAssertEqual(store.bag, GolfBag.standard)
        XCTAssertEqual(store.bag.distance(of: driver), 230)
        XCTAssertNil(store.bag.distance(of: putter))
        XCTAssertTrue(defaults.bool(forKey: GolfBagStore.seededKey))
        XCTAssertEqual(reopened().bag, GolfBag.standard, "The bag is saved")
    }

    func testTogglingTakesAClubOutAndPutsOneInAtItsDefault() {
        store.toggle(fiveWood)
        XCTAssertFalse(store.bag.contains(fiveWood))
        XCTAssertEqual(store.bag.clubs.count, 13)

        store.toggle(fourHybrid)
        XCTAssertEqual(store.bag.clubs.map(\.id).prefix(3), ["dr", "3w", "4h"])
        XCTAssertEqual(store.bag.distance(of: fourHybrid), 180)
        XCTAssertTrue(store.bag.isFull)
        XCTAssertEqual(reopened().bag, store.bag)
    }

    func testAFullBagTakesNoMoreClubs() {
        store.toggle(twoWood)

        XCTAssertEqual(store.bag, GolfBag.standard)
    }

    func testSetDistanceIsSaved() {
        store.setDistance(250, for: driver)

        XCTAssertEqual(store.bag.distance(of: driver), 250)
        XCTAssertEqual(reopened().bag.distance(of: driver), 250)
    }

    func testSetDistanceIgnoresClubsOutOfTheBagAndThePutter() {
        store.setDistance(200, for: twoWood)
        store.setDistance(10, for: putter)

        XCTAssertEqual(store.bag, GolfBag.standard)
        XCTAssertNil(store.bag.distance(of: twoWood))
        XCTAssertNil(store.bag.distance(of: putter))
    }

    func testAClubPutBackStartsOverAtItsDefault() {
        store.setDistance(250, for: driver)
        store.toggle(driver)
        store.toggle(driver)

        XCTAssertEqual(store.bag.distance(of: driver), 230)
    }

    func testAnEmptiedBagStaysEmpty() {
        for club in GolfBag.standard.clubs {
            store.toggle(club)
        }
        XCTAssertEqual(store.bag.clubs, [])

        XCTAssertEqual(reopened().bag.clubs, [], "The standard bag is seeded once, not whenever the bag is empty")
    }

    func testRowsThatAreNotClubsAreLeftOut() throws {
        let row = CarriedClub(driver)
        row.clubID = "bogus"
        container.mainContext.insert(row)
        try container.mainContext.save()

        XCTAssertEqual(reopened().bag, GolfBag.standard)
    }

    func testSeedingKeepsRowsAlreadyInTheStore() throws {
        store.toggle(fiveWood)
        defaults.removeObject(forKey: GolfBagStore.seededKey)

        let again = reopened()

        XCTAssertFalse(again.bag.contains(fiveWood), "Rows already saved are kept, not replaced by the standard bag")
        XCTAssertEqual(again.bag.clubs.count, 13)
    }

}
