import CourseDataSwift
import XCTest
@testable import SpotGolf

/// The Caddie's club and aim from each tee at Broadlands, with the standard bag. See
/// plans/2026-11-02-caddie-club-and-aim.md, section 7.
@MainActor
final class ClubAdviceRealCourseTests: XCTestCase {
    private var course: Course!

    override func setUp() async throws {
        try await super.setUp()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Broadlands-Golf-Course.json", withExtension: "gz"))
        course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: url).gzipDecompressed())
    }

    override func tearDown() async throws {
        course = nil
        try await super.tearDown()
    }

    private let clubs: [(club: Club, distance: ClubDistance)] = GolfBag.standard.clubs.compactMap { club in
        guard club.kind != .putter, let yards = GolfBag.standard.distance(of: club) else { return nil }
        return (club: club, distance: ClubDistance(startingDistance: yards, shots: []))
    }

    private struct Tee {
        let name: String
        let lies: LieGrid
        let start: GroundPoint
        let pin: GroundPoint
    }

    /// Every hole's first tee box, with its green's center as the pin.
    private var tees: [Tee] {
        course.subCourses.flatMap { nine in
            nine.holes.compactMap { hole -> Tee? in
                guard let green = hole.green(from: course.features), let tee = hole.teeBoxes(from: course.features).first
                else { return nil }
                let lies = LieGrid(course: course, hole: hole, plane: GroundPlane(origin: green.center))
                return Tee(name: "\(nine.name) \(hole.number)", lies: lies, start: lies.plane.point(tee.center),
                           pin: lies.plane.point(green.center))
            }
        }
    }

    /// The share of the pattern's spots in `lie`.
    private func share(_ pattern: ShotPattern, _ lie: Lie, lies: LieGrid) -> Double {
        let spots = pattern.spots
        return Double(spots.filter { lies.lie(at: $0) == lie }.count) / Double(spots.count)
    }

    func testTheAdviceSteersAwayFromWaterAndIsQuick() throws {
        let tees = tees
        XCTAssertGreaterThanOrEqual(tees.count, 18)
        var steered = 0
        for tee in tees {
            let started = Date()
            let advice = try XCTUnwrap(ClubAdvice.best(from: tee.start, pin: tee.pin, clubs: clubs, missAngle: 6.4,
                                                       lies: tee.lies))
            let firstRun = Date().timeIntervalSince(started)
            let again = Date()
            _ = ClubAdvice.best(from: tee.start, pin: tee.pin, clubs: clubs, missAngle: 6.4, lies: tee.lies)
            let secondRun = Date().timeIntervalSince(again)

            let distance = try XCTUnwrap(clubs.first { $0.club == advice.club }).distance
            let straight = ShotPattern(start: tee.start, heading: tee.start.heading(to: tee.pin), distance: distance,
                                       missAngle: 6.4)
            let water = share(advice.pattern, .water, lies: tee.lies)
            let straightWater = share(straight, .water, lies: tee.lies)
            XCTAssertLessThanOrEqual(water, straightWater + 1e-9,
                                     "\(tee.name): aiming at the pin should not be drier than the advice")
            if straightWater > water { steered += 1 }
            print(String(format: "%@: %@ %+d°, %.2f strokes, water %.0f%% (straight %.0f%%), sand %.0f%% (straight %.0f%%), %.0f ms then %.0f ms",
                         tee.name, advice.club.shortName, advice.aimOffset, advice.expectedStrokes, water * 100,
                         straightWater * 100, share(advice.pattern, .sand, lies: tee.lies) * 100,
                         share(straight, .sand, lies: tee.lies) * 100, firstRun * 1000, secondRun * 1000))
        }
        print("Steered away from water on \(steered) of \(tees.count) holes")
    }
}
