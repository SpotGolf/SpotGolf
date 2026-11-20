import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolfWatch

/// Replays real rounds through `HoleAdvancer`, the way each device feeds it. The rounds are the
/// exports in the git-ignored `Data/Simulations` folder, so this is skipped wherever they are
/// missing.
final class HoleAdvancerRealRoundTests: XCTestCase {

    private static let projectDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Broadlands, 2026-10-26: nine holes. Walnut Creek, 2026-11-17: eighteen, the back nine
    /// first, five of them with a walk of over 100 m from the green to the next tee.
    private static let rounds = ["broadlands-golf-course-2026-10-26", "walnut-creek-golf-preserve-2026-11-17"]

    /// An exported round's course, as picked for the round, and the watch's fixes.
    private func round(_ name: String) throws -> (selection: CourseSelection, fixes: [CLLocation]) {
        let folder = Self.projectDirectory.appendingPathComponent("Data/Simulations/\(name)")
        let streamURL = folder.appendingPathComponent("stream.bin")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: streamURL.path), "The real round is not on this machine")

        let selection = try JSONDecoder().decode(CourseSelection.self, from: Data(contentsOf: folder.appendingPathComponent("course.json")))
        let fixes = StreamRecord.records(in: try Data(contentsOf: streamURL)).compactMap { record -> CLLocation? in
            guard case .fix(let point) = record else { return nil }
            return CLLocation(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                              altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: point.timestamp)
        }
        return (selection, fixes)
    }

    func testTheDisplayHoleChangesAfterLeavingTheGreenAndByTheTee() throws {
        for name in Self.rounds {
            try checkEveryHoleChangesAfterLeavingTheGreenAndByTheTee(name, moving: .displayHole)
        }
    }

    /// The watch's hole also waits for the walk to bring the player near the next tee.
    func testThePlayingHoleChangesNearTheNextTee() throws {
        for name in Self.rounds {
            try checkEveryHoleChangesAfterLeavingTheGreenAndByTheTee(name, moving: .playingHole)
        }
    }

    /// Each hole changes after the player's last fix on the green and no later than reaching
    /// the next tee, and the round ends on its last hole.
    private func checkEveryHoleChangesAfterLeavingTheGreenAndByTheTee(_ name: String, moving target: HoleAdvancer.Target) throws {
        let (selection, fixes) = try round(name)
        let holes = selection.orderedHoles
        var advancer = HoleAdvancer(moving: target)
        var holeIndex = 0
        var holeStart = 0

        for (index, location) in fixes.enumerated() {
            guard let next = advancer.advance(location: location, courseSelection: selection, holeIndex: holeIndex) else { continue }
            let green = HoleShape(hole: holes[holeIndex], course: selection.course)
            let tees = HoleShape(hole: holes[next], course: selection.course)
            let reachedTee = fixes[holeStart...].firstIndex { tees.metersToTee(Self.coordinate($0)) == 0 } ?? fixes.endIndex
            // The player's real exit: the last fix at the green before walking onto the next tee
            let lastOnGreen = try XCTUnwrap(fixes[holeStart..<reachedTee].lastIndex { green.metersToGreen(Self.coordinate($0)).map { $0 <= 5 } ?? false },
                                            "\(name): hole \(holeIndex + 1) changed before the player reached its green")

            XCTAssertGreaterThan(index, lastOnGreen, "\(name): hole \(holeIndex + 1) changed before the player left its green")
            XCTAssertLessThanOrEqual(index, reachedTee, "\(name): hole \(next + 1) started after its tee was reached")
            if target == .playingHole {
                let toTee = try XCTUnwrap(tees.metersToTee(Self.coordinate(location)))
                XCTAssertLessThanOrEqual(toTee, HoleAdvancer.nearTeeDistance, "\(name): hole \(next + 1) started away from its tee")
            }
            holeIndex = next
            holeStart = index
        }

        XCTAssertEqual(holeIndex, holes.count - 1, "\(name): the round should end on its last hole")
    }

    private static func coordinate(_ location: CLLocation) -> Coordinate {
        Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
    }
}
