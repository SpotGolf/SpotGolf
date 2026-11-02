import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolfWatch

/// Replays the 2026-10-26 Broadlands round, the front nine, through `RoundEndPrompter` the way
/// the watch feeds it. The stream and the course are in `TestFixtures`.
final class RoundEndPrompterRealRoundTests: XCTestCase {

    private static let projectDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    /// When the round started on the phone. The player ended it 2:01:30 in.
    private static let roundStart = Date(timeIntervalSince1970: 1_793_039_221.414)

    private func broadlands() throws -> (selection: CourseSelection, records: [StreamRecord]) {
        let fixtures = Self.projectDirectory.appendingPathComponent("TestFixtures")
        let courseData = try Data(contentsOf: fixtures.appendingPathComponent("Broadlands-Golf-Course.json.gz"))
        let course = try JSONDecoder().decode(Course.self, from: courseData.gzipDecompressed())
        let stream = try Data(contentsOf: fixtures.appendingPathComponent("broadlands-2026-10-26-stream.bin"))
        return (CourseSelection(course: course, selectedSubCourseIndices: [0]), StreamRecord.records(in: stream))
    }

    private static func time(_ minutes: Int, _ seconds: Int) -> Date {
        roundStart.addingTimeInterval(TimeInterval(minutes * 60 + seconds))
    }

    /// Asks once, 2:01:07 in, 5 minutes after leaving the 9th green. The round would end at the
    /// last fix on that green, 1:55:35 in, 12 s after the last putt.
    func testAsksOnceAfterLeavingTheNinthGreen() throws {
        let (selection, records) = try broadlands()
        var prompter = RoundEndPrompter(courseSelection: selection, lastHoleIndex: selection.orderedHoles.count - 1)
        var changes: [(change: RoundEndPrompter.Change, at: Date)] = []

        for case .fix(let point) in records {
            let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                                      altitude: 0, horizontalAccuracy: point.horizontalAccuracy ?? 5, verticalAccuracy: 5,
                                      timestamp: point.timestamp)
            if let change = prompter.update(location: location) {
                changes.append((change, point.timestamp))
            }
        }

        XCTAssertEqual(changes.map(\.change), [.ask])
        let askedAt = try XCTUnwrap(changes.first?.at)
        XCTAssertEqual(askedAt.timeIntervalSince(Self.time(121, 7)), 0, accuracy: 5)
        let endTime = try XCTUnwrap(prompter.endTime)
        XCTAssertEqual(endTime.timeIntervalSince(Self.time(115, 35)), 0, accuracy: 5)
        // Swings during the walk to the car did not restart the wait
        let swingsAfterLeaving = records.filter { record in
            guard case .swing = record else { return false }
            return record.timestamp > endTime && record.timestamp < askedAt
        }
        XCTAssertGreaterThan(swingsAfterLeaving.count, 5)
        XCTAssertEqual(prompter.check(at: askedAt.addingTimeInterval(RoundEndPrompter.autoEndDelay)), .end(at: endTime))
    }
}
