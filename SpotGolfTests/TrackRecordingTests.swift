import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// Plays the first three holes at Broadlands with `RoundSimulator` and records the GPS fixes the
/// way the app does: one fix per delegate call, passed from `LocationManager` to `TrackStore`.
@MainActor
final class TrackRecordingTests: XCTestCase {

    // Core Location delivers about one fix per second with `kCLDistanceFilterNone`
    private static let fixInterval: TimeInterval = 1
    private static let secondsPerHole = 15 * 60
    private static let holeNumbers = 1...3
    private static let fixCount = 2_700

    private var directory: URL!
    private var store: TrackStore!
    private var locationManager: LocationManager!
    private var course: Course!
    private let roundID = UUID()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = TrackStore(directory: directory)
        locationManager = LocationManager()

        // The course file CourseBuilder produced, as published in CourseData
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Broadlands-Golf-Course.json", withExtension: "gz"))
        course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: url).gzipDecompressed())
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        course = nil
        locationManager = nil
        store = nil
        directory = nil
        super.tearDown()
    }

    /// The same round on every run: Front nine, Blue tees.
    private func playRound(seed: UInt64 = 2026) -> SimulatedRound {
        var simulator = RoundSimulator(course: course, subCourseIndex: 0, teeName: "Blue", seed: seed)
        return simulator.play(holeNumbers: Self.holeNumbers, start: start, secondsPerHole: Self.secondsPerHole)
    }

    private func meters(_ a: Coordinate, _ b: Coordinate) -> Double {
        a.clLocation.distance(from: b.clLocation)
    }

    // MARK: - Recording

    func testRecordsThreeHolesAtFifteenMinutesEach() throws {
        let round = playRound()
        XCTAssertEqual(round.fixes.count, Self.fixCount)

        // Same wiring as the app: every raw fix goes straight to the track
        let tracks = store!
        let id = roundID
        locationManager.onRawLocations = { tracks.append($0, roundID: id) }

        let manager = CLLocationManager()
        for fix in round.fixes {
            locationManager.locationManager(manager, didUpdateLocations: [fix])
        }
        store.flush()

        let points = store.points(for: roundID, source: .current)
        XCTAssertEqual(points.count, Self.fixCount)

        // One fix per second for 45 minutes, in order
        XCTAssertEqual(points.first?.timestamp, start)
        XCTAssertEqual(points.last?.timestamp, start.addingTimeInterval(45 * 60 - Self.fixInterval))
        let gaps = zip(points, points.dropFirst()).map { $1.timestamp.timeIntervalSince($0.timestamp) }
        XCTAssertTrue(gaps.allSatisfy { $0 == Self.fixInterval })

        // Every stored fix matches the fix that was delivered
        for (point, fix) in zip(points, round.fixes) {
            XCTAssertEqual(point.latitude, fix.coordinate.latitude, accuracy: 1e-7)
            XCTAssertEqual(point.longitude, fix.coordinate.longitude, accuracy: 1e-7)
            XCTAssertEqual(try XCTUnwrap(point.altitude), fix.altitude, accuracy: 0.01)
        }

        // 24 bytes per fix: 64,800 bytes for three holes
        let url = store.fileURL(for: roundID, source: .current)
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertEqual(size, Self.fixCount * TrackPoint.recordSize)
        XCTAssertEqual(size, 64_800)

        attach(round)
    }

    // MARK: - The simulated round

    func testRoundIsTheSameOnEveryRun() {
        let first = playRound(), second = playRound()
        XCTAssertEqual(first.shots, second.shots)
        XCTAssertEqual(first.fixes.map(\.coordinate.latitude), second.fixes.map(\.coordinate.latitude))
    }

    func testEveryHoleIsPlayedFromItsTeeToItsGreen() throws {
        let round = playRound()
        let holes = course.subCourses[0].holes

        for number in Self.holeNumbers {
            let hole = try XCTUnwrap(holes.first { $0.number == number })
            let shots = round.shots.filter { $0.holeNumber == number }
            let tee = try XCTUnwrap(hole.tees["Blue"].flatMap { course.findFeature(id: $0) })

            let first = try XCTUnwrap(shots.first), last = try XCTUnwrap(shots.last)
            XCTAssertTrue(PolygonGeometry.contains(first.ball, in: tee.polygon), "Hole \(number) should start on the Blue tee box")
            XCTAssertTrue(hole.onGreen(last.landing, from: course.features), "Hole \(number) should end in the hole on its green")
            XCTAssertTrue((hole.par - 1...hole.par + 3).contains(shots.count), "Hole \(number) took \(shots.count) strokes")

            // Each shot is played from where the last one landed
            for (shot, next) in zip(shots, shots.dropFirst()) {
                XCTAssertEqual(meters(shot.landing, next.ball), 0, accuracy: 0.01)
            }
        }
    }

    func testPlayerMovesLikeAPerson() {
        let round = playRound()

        // No jumps: a walking pace at most, even between holes
        let strides = zip(round.truePath, round.truePath.dropFirst()).map { meters($0, $1) }
        XCTAssertLessThan(strides.max() ?? 0, 2.5)

        // Never through the water
        let water = course.features.filter { $0.type == .water }
        for position in round.truePath {
            XCTAssertFalse(water.contains { PolygonGeometry.contains(position, in: $0.polygon) })
        }

        // Standing over the ball for the seconds before each swing
        for shot in round.shots {
            let index = Int(shot.time.timeIntervalSince(start))
            let before = round.truePath[(index - 8)..<index]
            XCTAssertTrue(before.allSatisfy { meters($0, shot.player) < 1.5 },
                          "Hole \(shot.holeNumber) stroke \(shot.stroke): the player should be at the ball")
        }

        // A good share of the round is spent walking, and a good share standing
        let walking = Double(strides.filter { $0 > 0.7 }.count) / Double(strides.count)
        XCTAssertTrue((0.3...0.8).contains(walking), "Walking for \(Int(walking * 100))% of the time")
    }

    func testOtherRoundsAlsoHoldUp() {
        let water = course.features.filter { $0.type == .water }
        let holes = course.subCourses[0].holes

        for seed in UInt64(1)...12 {
            let round = playRound(seed: seed)
            XCTAssertEqual(round.fixes.count, Self.fixCount, "Seed \(seed)")

            let strides = zip(round.truePath, round.truePath.dropFirst()).map { meters($0, $1) }
            XCTAssertLessThan(strides.max() ?? 0, 2.5, "Seed \(seed) jumps")

            let wet = round.truePath.filter { position in water.contains { PolygonGeometry.contains(position, in: $0.polygon) } }
            XCTAssertEqual(wet.count, 0, "Seed \(seed) walks through water")

            for number in Self.holeNumbers {
                let last = round.shots.last { $0.holeNumber == number }
                let hole = holes.first { $0.number == number }
                XCTAssertEqual(last.map { hole?.onGreen($0.landing, from: course.features) }, true, "Seed \(seed) hole \(number)")
            }
        }
    }

    func testGPSErrorIsRealistic() {
        let round = playRound()
        let errors = zip(round.fixes, round.truePath).map { meters(Coordinate($0.coordinate), $1) }

        let mean = errors.reduce(0, +) / Double(errors.count)
        XCTAssertTrue((1.5...4).contains(mean), "Mean GPS error \(mean) m")
        XCTAssertLessThan(errors.max() ?? 0, 12)
        XCTAssertTrue(round.fixes.allSatisfy { (3...15).contains($0.horizontalAccuracy) && $0.verticalAccuracy > 0 })
    }

    // MARK: - Export

    /// Keeps the round with the test results, so it can be drawn on a map.
    private func attach(_ round: SimulatedRound) {
        let fixes = zip(round.fixes, round.truePath).map { fix, truth in
            [fix.coordinate.latitude, fix.coordinate.longitude, fix.altitude, fix.horizontalAccuracy,
             truth.latitude, truth.longitude]
        }
        let shots = round.shots.map { shot in
            ["hole": shot.holeNumber, "stroke": shot.stroke, "second": Int(shot.time.timeIntervalSince(start)),
             "player": [shot.player.latitude, shot.player.longitude],
             "ball": [shot.ball.latitude, shot.ball.longitude],
             "landing": [shot.landing.latitude, shot.landing.longitude]] as [String: Any]
        }
        let export: [String: Any] = ["secondsPerHole": Self.secondsPerHole, "fixes": fixes, "shots": shots]
        guard let data = try? JSONSerialization.data(withJSONObject: export) else { return }

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "simulated-round.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
