import Observation
import ActivityKit
import CoreLocation
import os

/// Follows the active round on the phone, with the app open or in the background: keeps location
/// updates on and shows the display hole in a Live Activity. The phone's GPS is only for showing
/// yards; the watch's GPS changes the hole.
@MainActor
@Observable
final class RoundTracker {
    private static let locationOwner = "round"

    private let rounds: RoundStore
    private let location: LocationManager
    /// False for UI tests, which do not need the Lock Screen.
    private let showsActivity: Bool
    private var trackedRoundID: UUID?
    private var activity: Activity<HoleActivityAttributes>?
    // The content the activity shows, so a fix that changes nothing sends no update
    private var shownContent: HoleActivityAttributes.ContentState?

    init(rounds: RoundStore, location: LocationManager, showsActivity: Bool = true) {
        self.rounds = rounds
        self.location = location
        self.showsActivity = showsActivity

        rounds.addListener { [weak self] event in
            guard let self, case .roundsChanged = event else { return }
            roundsChanged(self.rounds.rounds)
        }
        location.addLocationListener { [weak self] in self?.locationChanged($0) }

        // Activities left from a round that is no longer active, after the app was closed
        let activeID = rounds.activeRound?.id
        for old in Activity<HoleActivityAttributes>.activities where old.attributes.roundID != activeID {
            Self.endActivity(id: old.id)
        }
        // A round already active at launch
        roundsChanged(rounds.rounds)
    }

    /// An activity can only be started with the app open, so one that could not start is
    /// tried again here.
    func appBecameActive() {
        startActivityIfMissing()
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
        Log.rounds.notice("Tracking round \(round.id) on the phone")
        trackedRoundID = round.id
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
            Self.endActivity(id: old.id)
        }
        activity = nil
        shownContent = nil
    }

    private func locationChanged(_ fix: CLLocation?) {
        guard let id = trackedRoundID, let fix, let round = rounds.round(id) else { return }
        updateActivity(round, location: fix)
    }

    // MARK: - Live Activity

    /// What the activity shows for `round`. An ended round shows no yards.
    static func content(_ round: Round, location: CLLocation?) -> HoleActivityAttributes.ContentState {
        HoleActivityAttributes.ContentState(
            holeNumber: round.displayHoleNumber,
            par: round.displayCourseHole?.par,
            yardsToGreen: round.isActive
                ? HoleOverview.yardsToPin(round, holeIndex: round.displayHoleIndex, from: location)
                : nil,
            toPin: round.hasKnownPin(holeIndex: round.displayHoleIndex),
            previousYards: HoleOverview.previousYards(strokes: round.displayHoleStrokes, from: round.isActive ? location : nil),
            holeStrokes: round.displayHoleStrokes.count,
            totalStrokes: round.allStrokes.count,
            toPar: HoleOverview.toPar(round))
    }

    private func startActivity(_ round: Round) {
        guard showsActivity, activity == nil else { return }
        // The activity outlives the app, so a relaunch during the round picks it up again.
        // Only one is kept: any other is from an earlier round or launch.
        let existing = Activity<HoleActivityAttributes>.activities
        Log.liveActivity.notice("Starting the Live Activity with \(existing.count) already running")
        let kept = existing.first(where: { $0.attributes.roundID == round.id })
        for old in existing where old.id != kept?.id {
            Self.endActivity(id: old.id)
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
            Log.liveActivity.error("Could not start the Live Activity: \(String(describing: error))")
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
        Self.updateActivity(id: activity.id, content: content)
    }

    // `Activity` is not Sendable, so the main actor can't call its async methods. Each change
    // runs in a task of its own, which looks the activity up by ID.

    private nonisolated static func activity(id: String) -> Activity<HoleActivityAttributes>? {
        Activity<HoleActivityAttributes>.activities.first { $0.id == id }
    }

    private nonisolated static func updateActivity(id: String, content: HoleActivityAttributes.ContentState) {
        Task.detached {
            await activity(id: id)?.update(ActivityContent(state: content, staleDate: nil))
        }
    }

    private nonisolated static func endActivity(id: String) {
        Task.detached {
            await activity(id: id)?.end(nil, dismissalPolicy: .immediate)
        }
    }
}
