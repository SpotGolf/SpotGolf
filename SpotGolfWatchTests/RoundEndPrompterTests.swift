import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolfWatch

final class RoundEndPrompterTests: XCTestCase {

    private static let metersPerDegreeLatitude = 111_320.0
    private static let metersPerDegreeLongitude = 111_320.0 * cos(33.0 * .pi / 180)
    /// Each green is a square this many meters from its center to its east edge.
    private static let greenEdge = 0.0001 * metersPerDegreeLongitude
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// The green of the hole at course-data index `index`: centered at (33 + index / 100, -97).
    private func greenCenter(_ index: Int) -> Coordinate {
        Coordinate(lat: 33.0 + Double(index) * 0.01, lon: -97.0)
    }

    private func makeGreen(id: Int, center: Coordinate) -> Feature {
        Feature(id: id, type: .green, polygon: [
            Coordinate(lat: center.lat - 0.0001, lon: center.lon - 0.0001),
            Coordinate(lat: center.lat - 0.0001, lon: center.lon + 0.0001),
            Coordinate(lat: center.lat + 0.0001, lon: center.lon + 0.0001),
            Coordinate(lat: center.lat + 0.0001, lon: center.lon - 0.0001),
            Coordinate(lat: center.lat - 0.0001, lon: center.lon - 0.0001),
        ])
    }

    /// Nines of `holes` holes each, every hole with a green unless `withoutGreens` names its number
    /// in the last nine. Greens are numbered across nines by course-data index.
    private func makeSelection(nines: Int = 1, holes: Int = 3, withoutGreens: Set<Int> = [],
                               startHoleIndex: Int = 0) -> CourseSelection {
        var features: [Feature] = []
        var subCourses: [SubCourse] = []
        for nine in 0..<nines {
            let nineHoles = (1...holes).map { number in
                let index = nine * holes + number - 1
                guard nine < nines - 1 || !withoutGreens.contains(number) else {
                    return Hole(number: number, par: 4, features: [])
                }
                let green = makeGreen(id: index + 1, center: greenCenter(index))
                features.append(green)
                return Hole(number: number, par: 4, features: [green.id])
            }
            subCourses.append(SubCourse(name: "Nine \(nine)", holes: nineHoles))
        }
        let course = Course(
            name: "Test Course", clubName: "Test Club",
            location: CourseLocation(address: "", city: "Test", state: "TX", country: "US",
                                     coordinate: Coordinate(lat: 0, lon: 0)),
            features: features, subCourses: subCourses
        )
        return CourseSelection(course: course, selectedSubCourseIndices: Array(0..<nines), startHoleIndex: startHoleIndex)
    }

    private func makePrompter(_ selection: CourseSelection) -> RoundEndPrompter {
        RoundEndPrompter(courseSelection: selection, lastHoleIndex: selection.orderedHoles.count - 1)
    }

    /// A fix `east` meters from the center of course-data green `green`, `second` seconds in.
    private func fix(green: Int = 2, east: Double, second: Double) -> CLLocation {
        let center = greenCenter(green)
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: center.lat,
                                                             longitude: center.lon + east / Self.metersPerDegreeLongitude),
                          altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start.addingTimeInterval(second))
    }

    /// Fixes once a second from `from`: `onGreen` at the green's center, then walking east from
    /// its edge at 1.5 m/s to 100 m past it, then standing there until `until`.
    private func visit(green: Int = 2, from: Int = 0, onGreen: Int, until: Int) -> [CLLocation] {
        var fixes = (0..<onGreen).map { fix(green: green, east: 0, second: Double(from + $0)) }
        var second = from + onGreen
        var east = Self.greenEdge
        while second < until {
            east = min(east + 1.5, Self.greenEdge + 100)
            fixes.append(fix(green: green, east: east, second: Double(second)))
            second += 1
        }
        return fixes
    }

    /// The first second, from the start, at least 20 m past the green's edge on `visit`'s walk.
    private func exitSecond(from: Int = 0, onGreen: Int) -> Double {
        Double(from + onGreen) + (20 / 1.5).rounded(.up) - 1
    }

    /// Each change and the second it came at.
    private func changes(_ prompter: inout RoundEndPrompter, _ fixes: [CLLocation]) -> [(change: RoundEndPrompter.Change, second: Double)] {
        fixes.compactMap { location in
            prompter.update(location: location).map { ($0, location.timestamp.timeIntervalSince(start)) }
        }
    }

    func testAsksFiveMinutesAfterLeavingTheFinalGreen() throws {
        var prompter = makePrompter(makeSelection())

        let result = changes(&prompter, visit(onGreen: 30, until: 600))

        let ask = try XCTUnwrap(result.first)
        XCTAssertEqual(ask.change, .ask)
        XCTAssertEqual(ask.second, exitSecond(onGreen: 30) + 300)
        XCTAssertEqual(result.count, 1)
    }

    func testOtherGreensNeverAsk() {
        var prompter = makePrompter(makeSelection())

        XCTAssertTrue(changes(&prompter, visit(green: 1, onGreen: 60, until: 900)).isEmpty)
    }

    func testFewerThanTwentyFixesOnTheGreenNeverAsks() {
        var prompter = makePrompter(makeSelection())

        XCTAssertTrue(changes(&prompter, visit(onGreen: 19, until: 900)).isEmpty)
    }

    func testBackOnTheGreenRestartsTheWait() throws {
        var prompter = makePrompter(makeSelection())
        // Back on the green 4 minutes after leaving it, and off again
        let fixes = visit(onGreen: 30, until: 300) + visit(from: 300, onGreen: 10, until: 1_000)

        let ask = try XCTUnwrap(changes(&prompter, fixes).first)

        XCTAssertEqual(ask.change, .ask)
        XCTAssertEqual(ask.second, exitSecond(from: 300, onGreen: 10) + 300)
    }

    func testBackOnTheGreenWhileAskingStopsAsking() {
        var prompter = makePrompter(makeSelection())
        let fixes = visit(onGreen: 30, until: 400) + visit(from: 400, onGreen: 10, until: 1_000)

        let result = changes(&prompter, fixes)

        XCTAssertEqual(result.map(\.change), [.ask, .stopAsking, .ask])
        XCTAssertEqual(result[1].second, 400)
        XCTAssertEqual(result[2].second, exitSecond(from: 400, onGreen: 10) + 300)
    }

    func testKeepPlayingStopsAskingForTheRound() {
        var prompter = makePrompter(makeSelection())
        XCTAssertEqual(changes(&prompter, visit(onGreen: 30, until: 400)).map(\.change), [.ask])

        prompter.keepPlaying()

        XCTAssertTrue(changes(&prompter, visit(from: 400, onGreen: 30, until: 4_000)).isEmpty)
        XCTAssertNil(prompter.check(at: start.addingTimeInterval(10_000)))
    }

    func testEndsTwentyMinutesAfterAskingAtTheLastFixOnTheGreen() {
        var prompter = makePrompter(makeSelection())

        let result = changes(&prompter, visit(onGreen: 30, until: 2_000))

        let askedAt = exitSecond(onGreen: 30) + 300
        XCTAssertEqual(result.map(\.change), [.ask, .end(at: start.addingTimeInterval(29))])
        XCTAssertEqual(result.map(\.second), [askedAt, askedAt + 1_200])
        XCTAssertEqual(prompter.endTime, start.addingTimeInterval(29))
    }

    func testChecksTheWaitsWhenNoFixesComeIn() {
        var prompter = makePrompter(makeSelection())
        let exit = exitSecond(onGreen: 30)
        _ = changes(&prompter, visit(onGreen: 30, until: Int(exit) + 1))

        XCTAssertNil(prompter.check(at: start.addingTimeInterval(exit + 299)))
        XCTAssertEqual(prompter.check(at: start.addingTimeInterval(exit + 300)), .ask)
        XCTAssertNil(prompter.check(at: start.addingTimeInterval(exit + 1_499)))
        XCTAssertEqual(prompter.check(at: start.addingTimeInterval(exit + 1_500)), .end(at: start.addingTimeInterval(29)))
        XCTAssertNil(prompter.check(at: start.addingTimeInterval(exit + 5_000)))
    }

    func testShotgunStartWatchesTheLastHoleInPlayingOrder() throws {
        // Two nines of 3, started on the 3rd: the 2nd (course-data index 1) is played last
        let selection = makeSelection(nines: 2, startHoleIndex: 2)
        var lastHole = makePrompter(selection)
        var sixth = makePrompter(selection)

        XCTAssertEqual(changes(&lastHole, visit(green: 1, onGreen: 30, until: 600)).map(\.change), [.ask])
        XCTAssertTrue(changes(&sixth, visit(green: 5, onGreen: 30, until: 600)).isEmpty)
    }

    func testFinalHoleWithoutAGreenNeverAsks() {
        var prompter = makePrompter(makeSelection(withoutGreens: [3]))

        XCTAssertTrue(changes(&prompter, visit(onGreen: 60, until: 3_000)).isEmpty)
        XCTAssertNil(prompter.check(at: start.addingTimeInterval(10_000)))
    }
}
