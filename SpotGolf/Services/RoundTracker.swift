import ActivityKit
import Combine
import CoreLocation
import UIKit
import os

/// Follows the active round on the phone, with the app open or in the background: keeps location
/// updates on, moves to the next hole, and shows the current hole in a Live Activity.
@MainActor
final class RoundTracker: ObservableObject {
    private static let locationOwner = "round"

    private let rounds: RoundStore
    private let location: LocationManager
    /// False for UI tests, which do not need the Lock Screen.
    private let showsActivity: Bool
    private var holeAdvancer = HoleAdvancer()
    private var trackedRoundID: UUID?
    private var activity: Activity<HoleActivityAttributes>?
    // The content the activity shows, so a fix that changes nothing sends no update
    private var shownContent: HoleActivityAttributes.ContentState?
    private var cancellables: Set<AnyCancellable> = []

    init(rounds: RoundStore, location: LocationManager, showsActivity: Bool = true) {
        self.rounds = rounds
        self.location = location
        self.showsActivity = showsActivity

        // Both publish before the value changes, so the new value is passed along
        rounds.$rounds
            .sink { [weak self] in self?.roundsChanged($0) }
            .store(in: &cancellables)
        location.$lastLocation
            .sink { [weak self] in self?.locationChanged($0) }
            .store(in: &cancellables)
        // An activity can only be started with the app open
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.startActivityIfMissing() }
            .store(in: &cancellables)

        // Activities left from a round that is no longer active, after the app was closed
        let activeID = rounds.activeRound?.id
        for old in Activity<HoleActivityAttributes>.activities where old.attributes.roundID != activeID {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Stops moving to the next hole while the user looks at another one.
    func pauseAdvance() {
        holeAdvancer.pause()
    }

    func resumeAdvance() {
        holeAdvancer.resume()
    }

    // MARK: - Round

    private func roundsChanged(_ all: [Round]) {
        let active = all.first(where: \.isActive)
        if active?.id != trackedRoundID {
            if trackedRoundID != nil {
                stopTracking()
            }
            if let active {
                startTracking(active)
            }
        }
        if let active {
            updateActivity(active, location: location.lastLocation)
        }
    }

    private func startTracking(_ round: Round) {
        Log.rounds.notice("Tracking round \(round.id, privacy: .public) on the phone")
        trackedRoundID = round.id
        holeAdvancer = HoleAdvancer()
        location.setUpdatesInBackground(true)
        location.startUpdating(for: Self.locationOwner)
        startActivity(round)
    }

    private func stopTracking() {
        Log.rounds.notice("Stopped tracking the round on the phone")
        trackedRoundID = nil
        location.setUpdatesInBackground(false)
        location.stopUpdating(for: Self.locationOwner)
        // Every one, in case an earlier launch left one behind
        for old in Activity<HoleActivityAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
        shownContent = nil
    }

    private func locationChanged(_ fix: CLLocation?) {
        guard let id = trackedRoundID, let fix, let round = rounds.round(id) else { return }
        if !holeAdvancer.isPaused,
           let next = holeAdvancer.advance(location: fix, courseSelection: round.courseSelection,
                                           currentHoleIndex: round.currentHoleIndex) {
            rounds.startHole(next, roundID: id, source: .autoAdvance)
        }
        if let round = rounds.round(id) {
            updateActivity(round, location: fix)
        }
    }

    // MARK: - Live Activity

    /// What the activity shows for `round`. An ended round shows no yards.
    static func content(_ round: Round, location: CLLocation?) -> HoleActivityAttributes.ContentState {
        HoleActivityAttributes.ContentState(
            holeNumber: round.currentHoleNumber,
            par: round.currentCourseHole?.par,
            yardsToGreen: round.isActive
                ? HoleOverview.yardsToGreenCenter(round, holeIndex: round.currentHoleIndex, from: location)
                : nil,
            previousYards: HoleOverview.previousYards(strokes: round.strokes, from: round.isActive ? location : nil),
            holeStrokes: round.strokes.count,
            totalStrokes: round.allStrokes.count,
            toPar: HoleOverview.toPar(round))
    }

    private func startActivity(_ round: Round) {
        guard showsActivity, activity == nil else { return }
        // The activity outlives the app, so a relaunch during the round picks it up again.
        // Only one is kept: any other is from an earlier round or launch.
        let existing = Activity<HoleActivityAttributes>.activities
        Log.liveActivity.notice("Starting the Live Activity with \(existing.count, privacy: .public) already running")
        let kept = existing.first(where: { $0.attributes.roundID == round.id })
        for old in existing where old.id != kept?.id {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        if let kept {
            activity = kept
            shownContent = nil
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.liveActivity.notice("Live Activities are turned off")
            return
        }
        let content = Self.content(round, location: location.lastLocation)
        let attributes = HoleActivityAttributes(roundID: round.id,
                                                courseName: Round.shortenCourseName(round.course.name))
        do {
            activity = try Activity.request(attributes: attributes,
                                            content: ActivityContent(state: content, staleDate: nil))
            shownContent = content
            Log.liveActivity.notice("Live Activity started")
        } catch {
            // Tried again when the app next becomes active
            Log.liveActivity.error("Could not start the Live Activity: \(String(describing: error), privacy: .public)")
        }
    }

    private func startActivityIfMissing() {
        guard activity == nil, let id = trackedRoundID, let round = rounds.round(id) else { return }
        startActivity(round)
    }

    private func updateActivity(_ round: Round, location: CLLocation?) {
        guard let activity else { return }
        let content = Self.content(round, location: location)
        guard content != shownContent else { return }
        shownContent = content
        Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
    }
}
