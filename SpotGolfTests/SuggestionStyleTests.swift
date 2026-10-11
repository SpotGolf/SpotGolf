import SwiftUI
import XCTest
@testable import SpotGolf

/// The suggestion pins' colors: green for a swing the watch felt, purple for a putt it heard,
/// orange for a stop, and a legend entry for each.
final class SuggestionStyleTests: XCTestCase {

    func testEachKindOfSuggestionHasItsOwnColor() {
        XCTAssertEqual(SuggestionStyle(.swing(peakG: 20)), .swing)
        XCTAssertEqual(SuggestionStyle(.contact(score: 0.9)), .contact)
        XCTAssertEqual(SuggestionStyle(.stop(duration: 12)), .stop)
        XCTAssertEqual(SuggestionStyle.swing.color, .green)
        XCTAssertEqual(SuggestionStyle.contact.color, .purple)
        XCTAssertEqual(SuggestionStyle.stop.color, .orange)
    }

    func testOnlyAHeardPuttShowsAFlag() {
        XCTAssertEqual(SuggestionStyle.contact.symbolName, "flag.fill")
        XCTAssertEqual(SuggestionStyle.swing.symbolName, "plus")
        XCTAssertEqual(SuggestionStyle.stop.symbolName, "plus")
    }

    func testTheLegendNamesEveryStyleOnce() {
        XCTAssertEqual(SuggestionStyle.allCases.count, 3)
        XCTAssertEqual(Set(SuggestionStyle.allCases.map { $0.title(minStop: 30) }).count, 3)
        XCTAssertEqual(Set(SuggestionStyle.allCases.map(\.colorName)).count, 3)
    }

    func testTheStopLabelFollowsTheStationaryThreshold() {
        XCTAssertEqual(SuggestionStyle.stop.title(minStop: 30), "30s stop")
        XCTAssertEqual(SuggestionStyle.stop.title(minStop: 45), "45s stop")
        XCTAssertEqual(SuggestionStyle.swing.title(minStop: 30), "Swing")
        XCTAssertEqual(SuggestionStyle.contact.title(minStop: 30), "Putt")
    }
}
