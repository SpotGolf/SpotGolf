import XCTest
@testable import SpotGolf

/// The map style: its choices, the map button's symbol for each, and the choice kept in the
/// settings.
final class MapStyleChoiceTests: XCTestCase {

    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        store = UserDefaults(suiteName: "MapStyleChoiceTests")!
        store.removePersistentDomain(forName: "MapStyleChoiceTests")
        SettingsKey.registerDefaults(in: store)
    }

    func testEveryChoiceRoundTripsThroughItsStoredValue() {
        for choice in MapStyleChoice.allCases {
            XCTAssertEqual(MapStyleChoice(rawValue: choice.rawValue), choice)
        }
        XCTAssertEqual(MapStyleChoice.allCases.count, 3)
    }

    func testTheButtonShowsAMapForTheDrawnMapAndAGlobeForPhotos() {
        XCTAssertEqual(MapStyleChoice.standard.symbolName, "map")
        XCTAssertTrue(MapStyleChoice.satellite.symbolName.hasPrefix("globe"))
        XCTAssertTrue(MapStyleChoice.hybrid.symbolName.hasPrefix("globe"))
        XCTAssertEqual(Set(MapStyleChoice.allCases.map(\.symbolName)).count, 3, "Each style has its own symbol")
    }

    func testTheStandardMapIsStoredByDefault() {
        XCTAssertEqual(MapStyleChoice.stored(in: store), .standard)
    }

    func testTheStoredChoiceIsReadBack() {
        MapStyleChoice.hybrid.store(in: store)
        XCTAssertEqual(store.string(forKey: SettingsKey.mapStyle), "hybrid")
        XCTAssertEqual(MapStyleChoice.stored(in: store), .hybrid)
    }

    func testAnUnknownStoredValueReadsAsTheStandardMap() {
        store.set("globe", forKey: SettingsKey.mapStyle)
        XCTAssertEqual(MapStyleChoice.stored(in: store), .standard)
    }

    func testResetPutsTheStyleBackToTheDefault() {
        MapStyleChoice.satellite.store(in: store)
        SettingsKey.reset(in: store)
        XCTAssertEqual(MapStyleChoice.stored(in: store), .standard)
    }
}
