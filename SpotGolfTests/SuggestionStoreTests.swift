import XCTest
@testable import SpotGolf

@MainActor
final class SuggestionStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testHiddenIDsArePerRound() {
        let store = SuggestionStore(directory: directory)
        let round = UUID()
        let suggestion = UUID()

        store.hide(suggestion, roundID: round)

        XCTAssertEqual(store.hiddenIDs(for: round), [suggestion])
        XCTAssertTrue(store.hiddenIDs(for: UUID()).isEmpty)
    }

    func testHiddenIDsSurviveAReload() {
        let round = UUID()
        let dismissed = UUID()
        let converted = UUID()
        let store = SuggestionStore(directory: directory)
        store.hide(dismissed, roundID: round)
        store.hide(converted, roundID: round)

        XCTAssertEqual(SuggestionStore(directory: directory).hiddenIDs(for: round), [dismissed, converted])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("suggestions.json").path))
    }

    func testDeleteRoundForgetsItsHiddenIDs() {
        let round = UUID()
        let store = SuggestionStore(directory: directory)
        store.hide(UUID(), roundID: round)

        store.deleteRound(round)

        XCTAssertTrue(store.hiddenIDs(for: round).isEmpty)
        XCTAssertTrue(SuggestionStore(directory: directory).hiddenIDs(for: round).isEmpty)
    }
}
