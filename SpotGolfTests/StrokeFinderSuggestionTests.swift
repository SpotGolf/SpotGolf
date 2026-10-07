import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// `StrokeFinder.suggestions` on hole 1 of `PathCourse`: a straight 300 m hole due north with a
/// 10 m tee box at the start and a 30 m green at the end.
final class StrokeFinderSuggestionTests: XCTestCase {

    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private let hole = HoleShape(hole: PathCourse.selection.orderedHoles[0], course: PathCourse.selection.course)

    /// A GPS track with one fix per second.
    private struct Track {
        var points: [TrackPoint] = []
        var seconds: TimeInterval = 0
        var north: Double = 0
        var east: Double = 0

        var now: Date { StrokeFinderSuggestionTests.start.addingTimeInterval(seconds) }

        mutating func stand(_ duration: Int) {
            for _ in 0..<duration { addFix() }
        }

        /// Walks in a straight line at 1.5 m/s.
        mutating func walk(north toNorth: Double, east toEast: Double = 0) {
            let distance = ((toNorth - north) * (toNorth - north) + (toEast - east) * (toEast - east)).squareRoot()
            let steps = max(Int((distance / 1.5).rounded(.up)), 1)
            let (fromNorth, fromEast) = (north, east)
            for step in 1...steps {
                let fraction = Double(step) / Double(steps)
                north = fromNorth + (toNorth - fromNorth) * fraction
                east = fromEast + (toEast - fromEast) * fraction
                addFix()
            }
        }

        /// A swing at the current time. The default is a full swing; a putt is about 5 g.
        func swing(peakG: Float = 20) -> StrokeSuggestion {
            .swing(at: now, peakG: peakG)
        }

        /// Ball contact at the current time. The default is a clear putt; a tap-in is about 1.5.
        func contact(score: Float = 5) -> ContactEvent {
            ContactEvent(timestamp: now, score: score, burst: 0.3, click: 20, turning: 1)
        }

        mutating func addFix(north: Double? = nil) {
            let point = PathCourse.coordinate(north: north ?? self.north, east: east)
            points.append(TrackPoint(timestamp: now, latitude: point.latitude, longitude: point.longitude, altitude: nil))
            seconds += 1
        }
    }

    private func suggestions(_ track: Track, _ swings: [StrokeSuggestion], contacts: [ContactEvent] = [],
                             minStop: TimeInterval = 30, hidden: Set<UUID> = []) -> [StrokeSuggestion] {
        StrokeFinder.suggestions(on: hole, points: track.points, swings: swings, contacts: contacts, minStop: minStop, hidden: hidden)
    }

    private func duration(of suggestion: StrokeSuggestion?) -> TimeInterval {
        guard case .stop(let duration) = suggestion?.kind else { return 0 }
        return duration
    }

    // MARK: - Full swings

    func testStrongestSwingAtTheSpotIsTheStroke() {
        var track = Track()
        track.walk(north: 150)
        track.stand(10)
        let practice = track.swing(peakG: 12)
        track.stand(10)
        let stroke = track.swing(peakG: 24)
        track.stand(10)
        let after = track.swing(peakG: 11)
        track.walk(north: 250)

        let found = suggestions(track, [practice, stroke, after])
        XCTAssertEqual(found.map(\.timestamp), [stroke.timestamp])
        XCTAssertEqual(found.first?.latitude ?? 0, PathCourse.coordinate(north: 150, east: 0).latitude, accuracy: 1e-6)
        XCTAssertEqual(found.first?.kind, .swing(peakG: 24))
    }

    func testSoftSwingInTheFairwayIsNotAStroke() {
        var track = Track()
        track.walk(north: 150)
        track.stand(20)
        let fidget = track.swing(peakG: 5)
        track.stand(20)
        track.walk(north: 250)

        XCTAssertTrue(suggestions(track, [fidget]).isEmpty)
    }

    func testShortStrokeCounts() {
        var track = Track()
        track.walk(north: 150)
        track.stand(20)
        let first = track.swing()
        track.stand(5)
        // Topped: the ball went 20 m
        track.walk(north: 170)
        track.stand(20)
        let second = track.swing()
        track.walk(north: 250)

        XCTAssertEqual(suggestions(track, [first, second]).map(\.timestamp), [first.timestamp, second.timestamp])
    }

    func testDuffHitAgainFromTheSameSpotWithinAMinuteIsOneStroke() {
        var track = Track()
        track.walk(north: 150)
        track.stand(20)
        let duff = track.swing(peakG: 20)
        track.stand(5)
        track.walk(north: 158)
        track.stand(20)
        let again = track.swing(peakG: 22)
        track.walk(north: 250)

        XCTAssertEqual(suggestions(track, [duff, again]).map(\.timestamp), [again.timestamp])
    }

    func testSecondStrokeFromTheSameSpotAfterAMinuteCounts() {
        var track = Track()
        track.walk(north: 150)
        track.stand(20)
        let first = track.swing()
        track.stand(70)
        let second = track.swing()
        track.walk(north: 250)

        XCTAssertEqual(suggestions(track, [first, second]).map(\.timestamp), [first.timestamp, second.timestamp])
    }

    func testStepBackForPracticeIsNotAStroke() {
        var track = Track()
        track.walk(north: 150)
        track.stand(20)
        let stroke = track.swing()
        track.stand(5)
        track.walk(north: 144, east: 2)
        track.stand(10)
        let practice = track.swing(peakG: 12)
        track.walk(north: 250)

        XCTAssertEqual(suggestions(track, [stroke, practice]).map(\.timestamp), [stroke.timestamp])
    }

    func testSwingWhileWalkingIsNotAStroke() {
        var track = Track()
        track.walk(north: 100)
        let twirl = track.swing()
        track.walk(north: 200)

        XCTAssertTrue(suggestions(track, [twirl]).isEmpty)
    }

    func testTeePracticeAtTwoSpotsIsOneStroke() {
        var track = Track()
        track.stand(20)
        let practice = track.swing(peakG: 12)
        track.walk(north: 0, east: 7)
        track.stand(30)
        let stroke = track.swing()
        track.walk(north: 150)

        let found = suggestions(track, [practice, stroke])
        XCTAssertEqual(found.map(\.timestamp), [stroke.timestamp])
        XCTAssertEqual(found.first?.longitude ?? 0, PathCourse.coordinate(north: 0, east: 7).longitude, accuracy: 1e-5)
    }

    func testReTeeIsASecondStroke() {
        var track = Track()
        track.stand(20)
        let lost = track.swing()
        track.walk(north: 0, east: 7)
        track.stand(120)
        let provisional = track.swing()
        track.walk(north: 150)

        XCTAssertEqual(suggestions(track, [lost, provisional]).map(\.timestamp), [lost.timestamp, provisional.timestamp])
    }

    func testSwingOffTheHoleIsNotAStroke() {
        var track = Track()
        track.walk(north: 150, east: 100)
        track.stand(20)
        let swing = track.swing()
        track.stand(20)

        XCTAssertTrue(suggestions(track, [swing]).isEmpty)
    }

    func testHoleWithNoShapesStillFindsStrokes() {
        var track = Track()
        track.stand(20)
        let first = track.swing()
        track.walk(north: 150)
        track.stand(20)
        let second = track.swing()
        track.walk(north: 250)

        let found = StrokeFinder.suggestions(on: HoleShape(), points: track.points, swings: [first, second], minStop: 30)
        XCTAssertEqual(found.map(\.timestamp), [first.timestamp, second.timestamp])
    }

    // MARK: - Putts and chips

    func testContactOnTheGreenIsAPutt() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let putt = track.contact()
        track.stand(20)

        let found = suggestions(track, [], contacts: [putt])
        XCTAssertEqual(found.map(\.timestamp), [putt.timestamp])
        XCTAssertEqual(found.first?.kind, .contact(score: 5))
        XCTAssertEqual(found.first?.id, StrokeSuggestion.id(at: putt.timestamp))
    }

    func testEveryPuttOnTheGreenCounts() {
        var track = Track()
        track.walk(north: 290)
        track.stand(20)
        let first = track.contact()
        // Walks 8 m to the ball, which is no closer to the green's edge
        track.walk(north: 298)
        track.stand(20)
        let second = track.contact()
        track.stand(5)

        XCTAssertEqual(suggestions(track, [], contacts: [first, second]).map(\.timestamp), [first.timestamp, second.timestamp])
    }

    func testPracticeStrokeJustBeforeThePuttIsOneStroke() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let practice = track.contact(score: 3)
        track.stand(3)
        let putt = track.contact(score: 8)
        track.stand(20)

        XCTAssertEqual(suggestions(track, [], contacts: [practice, putt]).map(\.timestamp), [putt.timestamp])
    }

    func testTapInAfterThePuttCounts() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let putt = track.contact()
        track.stand(12)
        let tapIn = track.contact(score: 1.5)
        track.stand(20)

        let found = suggestions(track, [], contacts: [putt, tapIn])
        XCTAssertEqual(found.map(\.timestamp), [putt.timestamp, tapIn.timestamp])
        XCTAssertEqual(found.last?.kind, .contact(score: 1.5))
    }

    func testWeakContactWithNoPuttBeforeItIsNotAStroke() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let brush = track.contact(score: 1.5)
        track.stand(20)

        let found = suggestions(track, [], contacts: [brush])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.isContact, false)
        XCTAssertEqual(found.first?.isSwing, false)
    }

    func testOneTapInPerPutt() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let putt = track.contact()
        track.stand(10)
        let tapIn = track.contact(score: 1.5)
        track.stand(10)
        let fidget = track.contact(score: 1.5)
        track.stand(20)

        XCTAssertEqual(suggestions(track, [], contacts: [putt, tapIn, fidget]).map(\.timestamp), [putt.timestamp, tapIn.timestamp])
    }

    func testTapInIsNotTheNextPuttsPracticeStroke() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let first = track.contact()
        track.stand(6)
        let practice = track.contact(score: 3)
        track.stand(2)
        let second = track.contact(score: 9)
        track.stand(20)

        XCTAssertEqual(suggestions(track, [], contacts: [first, practice, second]).map(\.timestamp), [first.timestamp, second.timestamp])
    }

    func testPuttsAfterAChipFromTheSameSpotCount() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let chip = track.swing(peakG: 15)
        track.stand(2)
        let chipContact = track.contact(score: 40)
        track.stand(20)
        let putt = track.contact()
        track.stand(12)
        let tapIn = track.contact(score: 1.5)
        track.stand(20)

        let found = suggestions(track, [chip], contacts: [chipContact, putt, tapIn])
        XCTAssertEqual(found.map(\.timestamp), [chip.timestamp, putt.timestamp, tapIn.timestamp])
        XCTAssertEqual(found.first?.isSwing, true)
    }

    func testSoftSwingOnTheGreenIsNotAStroke() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let fidget = track.swing(peakG: 5)
        track.stand(20)

        let found = suggestions(track, [fidget])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.isSwing, false)
    }

    func testStopWithAContactGetsNoStopSuggestion() {
        var track = Track()
        track.walk(north: 300)
        track.stand(30)
        let putt = track.contact()
        track.stand(30)

        XCTAssertEqual(suggestions(track, [], contacts: [putt]).map(\.kind), [.contact(score: 5)])
    }

    func testStopWithAFullSwingGetsNoPuttSuggestion() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        let chip = track.swing(peakG: 13)
        track.stand(10)
        let fidget = track.swing(peakG: 4)
        track.stand(20)

        XCTAssertEqual(suggestions(track, [chip, fidget]).map(\.timestamp), [chip.timestamp])
    }

    func testStopWithNoSwingNearTheGreenIsSuggested() {
        var track = Track()
        track.walk(north: 260) // 25 m short of the green's edge
        let arrived = track.now
        track.stand(40)
        track.walk(north: 300)

        let found = suggestions(track, [])
        XCTAssertEqual(found.count, 1)
        // A slow walk joins the stop a few fixes before the player stands still
        XCTAssertEqual(found.first?.timestamp.timeIntervalSince(arrived) ?? .infinity, 0, accuracy: 8)
        XCTAssertGreaterThanOrEqual(duration(of: found.first), 40)
    }

    func testStopWithNoSwingInTheFairwayIsNotSuggested() {
        var track = Track()
        track.walk(north: 150)
        track.stand(60)
        track.walk(north: 200)

        XCTAssertTrue(suggestions(track, []).isEmpty)
    }

    func testStopShorterThanTheStationaryThresholdIsNotSuggested() {
        var track = Track()
        track.walk(north: 300)
        track.stand(20)
        track.walk(north: 330)

        XCTAssertTrue(suggestions(track, [], minStop: 30).isEmpty)
        XCTAssertEqual(suggestions(track, [], minStop: 10).count, 1)
    }

    func testGPSSpikeDoesNotSplitTheStop() {
        var track = Track()
        track.walk(north: 300)
        track.stand(15)
        track.addFix(north: 315)
        track.stand(15)
        track.walk(north: 340, east: 40)

        let found = suggestions(track, [], minStop: 10)
        XCTAssertEqual(found.count, 1)
        XCTAssertGreaterThanOrEqual(duration(of: found.first), 31)
    }

    // MARK: - IDs

    func testIDComesFromTheFirstSwingSoTheRealSwingKeepsIt() {
        var track = Track()
        track.walk(north: 150)
        track.stand(10)
        let practice = track.swing(peakG: 12)
        track.stand(10)
        let stroke = track.swing()
        track.walk(north: 250)

        let beforeRealSwing = suggestions(track, [practice])
        let afterRealSwing = suggestions(track, [practice, stroke])
        XCTAssertEqual(beforeRealSwing.map(\.id), afterRealSwing.map(\.id))
        XCTAssertEqual(afterRealSwing.map(\.timestamp), [stroke.timestamp])
    }

    func testStopThatGainsAContactBecomesAPuttWithTheContactsID() {
        var track = Track()
        track.walk(north: 300)
        track.stand(40)
        let putt = ContactEvent(timestamp: track.now.addingTimeInterval(-10), score: 5, burst: 0.3, click: 20, turning: 1)
        track.walk(north: 340, east: 40)

        let withoutContact = suggestions(track, [])
        let withContact = suggestions(track, [], contacts: [putt])
        XCTAssertEqual(withoutContact.count, 1)
        XCTAssertEqual(withContact.map(\.id), [StrokeSuggestion.id(at: putt.timestamp)])
        XCTAssertEqual(withContact.first?.isContact, true)
    }

    func testStopInProgressKeepsItsID() {
        var track = Track()
        track.walk(north: 300)
        track.stand(40)
        let early = suggestions(track, [])
        track.stand(40)

        XCTAssertEqual(early.map(\.id), suggestions(track, []).map(\.id))
    }

    func testMovedHoleStartKeepsTheIDs() {
        var track = Track()
        track.stand(20)
        let teeShot = track.swing()
        track.walk(north: 150)
        track.stand(20)
        let second = track.swing()
        track.stand(5)
        let swings = [teeShot, second]
        let wholeRound = StrokeFinder.suggestions(on: HoleShape(), points: track.points, swings: swings, minStop: 30)

        // A hole boundary in the middle of the second stop moves that stop to the next hole
        let boundary = second.timestamp.addingTimeInterval(-10)
        let before = StrokeFinder.suggestions(on: HoleShape(), points: track.points, swings: swings,
                                              minStop: 30) { $0.end < boundary }
        let after = StrokeFinder.suggestions(on: HoleShape(), points: track.points, swings: swings,
                                             minStop: 30) { $0.end >= boundary }

        XCTAssertEqual(wholeRound.count, 2)
        XCTAssertEqual(before.map(\.timestamp), [teeShot.timestamp])
        XCTAssertEqual((before + after).map(\.id), wholeRound.map(\.id))
    }

    func testStopBelongsToTheHoleThePlayerLeftItOn() {
        var track = Track()
        track.walk(north: 300)
        track.stand(40)
        let stop = track.now
        track.walk(north: 340, east: 40)
        var round = Round(date: Self.start, courseSelection: PathCourse.selection)
        round.holeTimeline.append(HoleStart(holeIndex: 1, startedAt: track.now, source: .stroke))
        XCTAssertEqual(StrokeFinder.suggestions(in: round, holeIndex: 0, points: track.points, swings: [], minStop: 30).count, 1)

        // Hole 2 starts just after the stop begins, so the player left the stop on hole 2
        round.holeTimeline[1].startedAt = stop.addingTimeInterval(-35)
        XCTAssertTrue(StrokeFinder.suggestions(in: round, holeIndex: 0, points: track.points, swings: [], minStop: 30).isEmpty)
    }

    // MARK: - Hiding and the limit

    func testHiddenSuggestionsAreLeftOut() throws {
        var track = Track()
        track.stand(20)
        let teeShot = track.swing()
        track.walk(north: 150)
        track.stand(20)
        let second = track.swing()
        track.walk(north: 250)
        let first = try XCTUnwrap(suggestions(track, [teeShot, second]).first)

        XCTAssertEqual(suggestions(track, [teeShot, second], hidden: [first.id]).map(\.timestamp), [second.timestamp])
    }

    func testFullSwingsAreNeverCutByTheLimit() {
        var track = Track()
        var swings: [StrokeSuggestion] = []
        // Twelve strokes, each 20 m closer to the green and more than a minute apart
        for index in 0..<12 {
            track.walk(north: Double(index) * 20 + 10)
            track.stand(70)
            swings.append(track.swing())
        }

        XCTAssertEqual(suggestions(track, swings).map(\.timestamp), swings.map(\.timestamp))
    }

    func testPuttsFillTheLimitAfterFullSwings() {
        var track = Track()
        track.stand(20)
        let teeShot = track.swing()
        var putts: [ContactEvent] = []
        // Ten putts at ten spots from 25 m short of the green's edge onto it
        for index in 0..<10 {
            track.walk(north: 260 + Double(index) * 6)
            track.stand(20)
            putts.append(track.contact())
        }

        let found = suggestions(track, [teeShot], contacts: putts)
        XCTAssertEqual(found.count, StrokeFinder.maxPerHole)
        XCTAssertEqual(found.map(\.timestamp), [teeShot.timestamp] + putts.prefix(9).map(\.timestamp))
    }

    // MARK: - Stroke times

    func testEstimatedTimeIsTheNearestFix() throws {
        var track = Track()
        track.walk(north: 150)
        let there = track.now.addingTimeInterval(-1)
        track.walk(north: 250)
        let point = PathCourse.coordinate(north: 150, east: 2)
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))

        XCTAssertEqual(StrokeFinder.estimatedTime(of: stroke, in: track.points), there)
        XCTAssertNil(StrokeFinder.estimatedTime(of: stroke, in: []))
    }

    func testDistanceIsZeroInsideAndToTheNearestEdgeOutside() {
        let square = PathCourse.square(north: 0, east: 0, half: 10)

        XCTAssertEqual(HoleShape.distance(from: PathCourse.coordinate(north: 0, east: 0), to: square), 0)
        // 5 m out from the middle of an edge, far from any corner
        XCTAssertEqual(HoleShape.distance(from: PathCourse.coordinate(north: 0, east: 15), to: square), 5, accuracy: 0.1)
    }
}
