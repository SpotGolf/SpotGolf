import CoreLocation
import XCTest
@testable import SpotGolfWatch

/// The drills' flow: paused before each drill, one task at a time, and what `drill.json` holds.
final class DrillSessionTests: XCTestCase {
    private let twoDrills = [Drill.all[3], Drill.all[4]]

    func testReadyShowsTheFirstTaskAndDoneShowsTheNext() {
        var session = DrillSession()
        XCTAssertEqual(session.step, .paused(next: 0))
        XCTAssertFalse(session.collectsBalls, "Nothing to collect before the first drill")

        session.ready(at: 10)
        XCTAssertEqual(session.step, .task(drill: 0, task: 0))
        session.done(at: 15)
        XCTAssertEqual(session.step, .task(drill: 0, task: 1), "The next task shows at once")

        XCTAssertEqual(session.record.drills[0].ready, 10)
        XCTAssertEqual(session.record.tasks.count, 2)
        XCTAssertEqual(session.record.tasks[0], .init(drill: 1, task: 1, key: "putt3ft", start: 10, done: 15))
        XCTAssertEqual(session.record.tasks[1].start, 15)
        XCTAssertNil(session.record.tasks[1].done)
    }

    func testFiveTasksEndTheDrillAndPauseBeforeTheNext() {
        var session = DrillSession()
        session.ready(at: 0)
        for task in 1...Drill.tasks {
            session.done(at: Double(task))
        }

        XCTAssertEqual(session.step, .paused(next: 1))
        XCTAssertTrue(session.collectsBalls, "Putts use balls")
        XCTAssertEqual(session.currentDrill?.key, "practiceThenPutt10ft")
        XCTAssertEqual(session.drillsFinished, 1)
    }

    func testNoCollectingAfterADrillWithNoBall() {
        var session = DrillSession(drills: twoDrills)
        session.ready(at: 0)
        for task in 1...Drill.tasks { session.done(at: Double(task)) }
        XCTAssertTrue(session.collectsBalls, "Tap-ins use balls")
        session.ready(at: 10)
        for task in 1...Drill.tasks { session.done(at: Double(10 + task)) }

        XCTAssertEqual(session.step, .finished, "The last drill's last task ends the session")
        XCTAssertEqual(session.drillsFinished, 2)
    }

    func testSkipDrillGoesToTheNextPausedScreen() {
        var session = DrillSession()
        session.ready(at: 0)
        session.done(at: 1)

        session.skipDrill()

        XCTAssertEqual(session.step, .paused(next: 1))
        XCTAssertTrue(session.record.drills[0].skipped)
        XCTAssertFalse(session.collectsBalls, "A skipped drill may not have used the balls")
        XCTAssertEqual(session.drillsFinished, 0)

        session.skipDrill()
        XCTAssertEqual(session.step, .paused(next: 2), "Skipping from the paused screen skips that drill")
        XCTAssertTrue(session.record.drills[1].skipped)
        XCTAssertNil(session.record.drills[1].ready)
    }

    func testSkippingTheLastDrillFinishes() {
        var session = DrillSession(drills: twoDrills)
        session.skipDrill()
        session.skipDrill()

        XCTAssertEqual(session.step, .finished)
    }

    func testStopKeepsTheDrillsDone() {
        var session = DrillSession()
        session.ready(at: 0)
        for task in 1...Drill.tasks { session.done(at: Double(task)) }
        session.ready(at: 20)

        session.stop()

        XCTAssertEqual(session.step, .finished)
        XCTAssertEqual(session.drillsFinished, 1)
        XCTAssertNil(session.record.tasks.last?.done, "The task left open has no Done")
    }

    func testTapsInTheWrongStepAreIgnored() {
        var session = DrillSession()
        session.done(at: 1)
        XCTAssertEqual(session.step, .paused(next: 0), "No Done before Ready")
        session.ready(at: 2)
        session.ready(at: 3)
        XCTAssertEqual(session.record.drills[0].ready, 2, "No second Ready on a task")
    }

    func testRecordRoundTripsAsJSON() throws {
        var session = DrillSession()
        session.ready(at: 1.5)
        session.done(at: 3)

        let data = try JSONEncoder().encode(session.record)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual((json["drills"] as? [Any])?.count, Drill.all.count)
        XCTAssertEqual(try JSONDecoder().decode(DrillSession.Record.self, from: data), session.record)
    }

    func testEveryDrillTellsItsSetupAndTask() {
        XCTAssertEqual(Drill.all.count, 8)
        XCTAssertEqual(Set(Drill.all.map(\.key)).count, 8, "Keys are unique")
        for drill in Drill.all {
            XCTAssertTrue(drill.task.hasSuffix("then tap Done."), drill.task)
            XCTAssertFalse(drill.setup.isEmpty)
        }
    }
}

/// The session's one starting location.
final class StartingFixTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func fix(_ accuracy: Double, second: TimeInterval, latitude: Double = 39.955449, longitude: Double = -105.042216) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: start.addingTimeInterval(second))
    }

    func testAGoodFixIsKeptAtOnce() {
        var picker = StartingFix(startDate: start)
        XCTAssertFalse(picker.add([fix(65, second: 1)]))
        XCTAssertTrue(picker.add([fix(12, second: 2), fix(5, second: 3)]), "Updates can stop at 30 m or better")

        XCTAssertEqual(picker.location(sessionStart: start),
                       PuttSharing.Location(latitude: 39.9554, longitude: -105.0422, horizontalAccuracy: 12, t: 2))
    }

    func testWithOnlyWorseFixesTheBestIsKeptWhenTimeIsUp() {
        var picker = StartingFix(startDate: start)
        picker.add([fix(120, second: 1), fix(45, second: 2), fix(80, second: 3)])
        XCTAssertFalse(picker.isDone)

        picker.timeUp()

        XCTAssertTrue(picker.isDone)
        XCTAssertEqual(picker.location(sessionStart: start)?.horizontalAccuracy, 45)
    }

    func testNoFixGivesNoLocation() {
        var picker = StartingFix(startDate: start)
        picker.add([fix(-1, second: 1)])
        picker.timeUp()

        XCTAssertNil(picker.location(sessionStart: start))
    }

    func testRoundsToFourDecimalPlaces() {
        XCTAssertEqual(PuttSharing.Location.rounded(39.955449), 39.9554)
        XCTAssertEqual(PuttSharing.Location.rounded(-105.04226), -105.0423, accuracy: 1e-9)
    }
}
