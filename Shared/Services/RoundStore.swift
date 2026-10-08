import Foundation
import os
import CoreLocation
import CourseDataSwift

/// A change to the rounds, passed to every listener while the change is made.
enum RoundEvent {
    /// Any change to `rounds`, from either device.
    case roundsChanged
    /// A timeline change made on this device: a hole's first stroke, or a start time set by hand.
    case timelineChanged(Round)
    /// A display hole change made on this device.
    case displayHoleChanged(Round)
    /// A pin set on this device.
    case pinsChanged(Round)
    /// A stroke change made on this device.
    case strokesChanged(Round)
}

/// Holds and saves every round. Changes made on this device are reported to listeners as
/// `RoundEvent`s so they can be sent to the other device; changes applied from the other
/// device are only reported as `roundsChanged`.
@MainActor
class RoundStore: ObservableObject {
    @Published var rounds: [Round] = [] {
        didSet {
            save()
            report(.roundsChanged)
        }
    }

    // Run in the order added, during the change, so messages to the other device keep its order
    private var listeners: [(RoundEvent) -> Void] = []

    private let fileURL: URL

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent("rounds.json")
        load()
    }

    /// Adds a listener for every later change. Listeners stay for the store's life.
    func addListener(_ listener: @escaping (RoundEvent) -> Void) {
        listeners.append(listener)
    }

    private func report(_ event: RoundEvent) {
        for listener in listeners {
            listener(event)
        }
    }

    /// The round being recorded.
    var activeRound: Round? {
        rounds.first(where: \.isActive)
    }

    /// The round that has not ended yet: starting, active, or ending.
    var currentRound: Round? {
        rounds.first(where: \.isInProgress)
    }

    func round(_ id: UUID) -> Round? {
        rounds.first(where: { $0.id == id })
    }

    /// Changes a round in place and saves. Does nothing for an unknown round.
    func update(_ id: UUID, _ change: (inout Round) -> Void) {
        guard let index = rounds.firstIndex(where: { $0.id == id }) else { return }
        var round = rounds[index]
        change(&round)
        // Every change rewrites the whole file, so a change that changes nothing is skipped
        guard round != rounds[index] else { return }
        rounds[index] = round
    }

    // MARK: - Rounds

    /// Adds a new round. An existing round with the same ID is returned unchanged.
    @discardableResult
    func startRound(id: UUID = UUID(), date: Date = Date(), courseSelection: CourseSelection,
                    status: RoundStatus = .active) -> Round {
        if let existing = round(id) { return existing }
        let round = Round(id: id, date: date, status: status, courseSelection: courseSelection)
        rounds.insert(round, at: 0)
        return round
    }

    func deleteRound(_ id: UUID) {
        guard rounds.contains(where: { $0.id == id }) else { return }
        rounds.removeAll { $0.id == id }
    }

    // MARK: - Display hole

    /// Shows a hole on both devices. The active round when `roundID` is nil.
    func setDisplayHole(_ index: Int, roundID: UUID? = nil, at date: Date = Date()) {
        guard let id = roundID ?? activeRound?.id,
              let i = rounds.firstIndex(where: { $0.id == id }) else { return }
        var round = rounds[i]
        guard round.setDisplayHole(index, at: date) else { return }
        rounds[i] = round
        report(.displayHoleChanged(round))
    }

    /// Takes the other device's display hole when it is newer. Returns true if it changed.
    @discardableResult
    func mergeDisplayHole(_ displayHole: DisplayHole, roundID: UUID) -> Bool {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return false }
        var round = rounds[i]
        guard round.mergeDisplayHole(displayHole) else { return false }
        rounds[i] = round
        return true
    }

    // MARK: - Pins

    /// Sets the pin on a hole, in the active round when `roundID` is nil. Does nothing when the
    /// point is not on that hole's green.
    func setPin(_ coordinate: CLLocationCoordinate2D, holeIndex: Int, roundID: UUID? = nil, at date: Date = Date()) {
        guard let id = roundID ?? activeRound?.id,
              let i = rounds.firstIndex(where: { $0.id == id }) else { return }
        var round = rounds[i]
        guard round.setPin(coordinate, onHole: holeIndex, at: date) else { return }
        rounds[i] = round
        report(.pinsChanged(round))
    }

    /// Gives every hole with a green and no pin a pin at the green's center, when a round starts
    /// or resumes. Reported like a pin set here, so the other device gets them too.
    func addCenterPins(roundID: UUID) {
        changePins(roundID) { $0.addCenterPins() }
    }

    /// Adds other golfers' pins, by the merge rules. Reported like a pin set here, so the other
    /// device gets them too.
    func addSharedPins(_ pins: [PinLocation], roundID: UUID) {
        changePins(roundID) { $0.mergePins(pins) }
    }

    private func changePins(_ roundID: UUID, _ change: (inout Round) -> Bool) {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        var round = rounds[i]
        guard change(&round) else { return }
        rounds[i] = round
        report(.pinsChanged(round))
    }

    /// Takes the other device's pins that replace this one's. Returns true if any changed.
    @discardableResult
    func mergePins(_ pins: [PinLocation], roundID: UUID) -> Bool {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return false }
        var round = rounds[i]
        guard round.mergePins(pins) else { return false }
        rounds[i] = round
        return true
    }

    // MARK: - Hole timeline

    /// Merges the other device's timeline. Returns true if anything changed.
    @discardableResult
    func mergeTimeline(_ entries: [HoleStart], roundID: UUID) -> Bool {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return false }
        var round = rounds[i]
        guard round.mergeTimeline(entries) else { return false }
        rounds[i] = round
        return true
    }

    /// Replaces the timeline with one changed on this device.
    func setTimeline(_ entries: [HoleStart], roundID: UUID) {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        let normalized = HoleTimeline.normalized(entries)
        guard normalized != rounds[i].holeTimeline else { return }
        var round = rounds[i]
        round.holeTimeline = normalized
        rounds[i] = round
        report(.timelineChanged(round))
    }

    /// Sets a timeline entry's start time, as the user's own correction. The time is kept
    /// between the entries before and after it, so the order of holes never changes.
    func setStartTime(_ date: Date, entryID: UUID, roundID: UUID) {
        guard var entries = round(roundID)?.holeTimeline,
              let i = entries.firstIndex(where: { $0.id == entryID }),
              let range = Self.startTimeRange(for: entryID, in: entries) else { return }
        entries[i].startedAt = min(max(date, range.lowerBound), range.upperBound)
        entries[i].source = .userSet
        entries[i].version += 1
        setTimeline(entries, roundID: roundID)
    }

    /// The start times an entry can have: after the entry before it and before the one after it.
    /// Nil for the first entry, which is the round's start.
    static func startTimeRange(for entryID: UUID, in entries: [HoleStart]) -> ClosedRange<Date>? {
        guard let i = entries.firstIndex(where: { $0.id == entryID }), i > 0 else { return nil }
        let lower = entries[i - 1].startedAt.addingTimeInterval(1)
        let upper = i + 1 < entries.count ? entries[i + 1].startedAt.addingTimeInterval(-1) : .distantFuture
        return lower <= upper ? lower...upper : nil
    }

    // MARK: - Strokes

    /// Adds a stroke. `hitAt` is when it was hit, when known: a hole's first stroke starts the
    /// hole in the timeline, and an earlier one added later moves the start back.
    func addStroke(to roundID: UUID, holeIndex: Int, stroke: Stroke, hitAt: Date? = nil) {
        var added = false
        changeStrokes(roundID) { round in
            guard !round.hasStroke(id: stroke.id) else { return false }
            round.addStroke(stroke, toHoleIndex: holeIndex)
            added = true
            return true
        }
        guard added, let hitAt, let i = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        var round = rounds[i]
        guard round.strokeHit(onHole: holeIndex, at: hitAt) else { return }
        rounds[i] = round
        report(.timelineChanged(round))
    }

    func moveStroke(_ stroke: Stroke, to coordinate: CLLocationCoordinate2D, in roundID: UUID) {
        changeStroke(stroke.id, in: roundID) { existing in
            existing = Stroke(id: existing.id, coordinate: coordinate, type: existing.type)
        }
    }

    func setStrokeType(strokeID: UUID, type: StrokeType, in roundID: UUID) {
        changeStroke(strokeID, in: roundID) { $0.type = type }
    }

    func reorderStroke(_ stroke: Stroke, to newIndex: Int, in roundID: UUID) {
        changeStrokes(roundID) { round in
            guard let holeIndex = round.holeIndex(containing: stroke.id),
                  let strokeIndex = round.holes[holeIndex].strokes.firstIndex(where: { $0.id == stroke.id }) else { return false }
            let clamped = min(max(newIndex, 0), round.holes[holeIndex].strokes.count - 1)
            guard clamped != strokeIndex else { return false }
            let removed = round.holes[holeIndex].strokes.remove(at: strokeIndex)
            round.holes[holeIndex].strokes.insert(removed, at: clamped)
            return true
        }
    }

    func removeStroke(_ stroke: Stroke, from roundID: UUID) {
        changeStrokes(roundID) { round in
            guard let holeIndex = round.holeIndex(containing: stroke.id) else { return false }
            round.holes[holeIndex].strokes.removeAll { $0.id == stroke.id }
            return true
        }
    }

    /// Applies the phone's strokes on the watch when the snapshot is newer than the last one applied.
    @discardableResult
    func applyStrokes(_ snapshot: StrokesSnapshot) -> Bool {
        guard let i = rounds.firstIndex(where: { $0.id == snapshot.roundID }),
              snapshot.version > rounds[i].strokesVersion else { return false }
        var round = rounds[i]
        var holes = snapshot.holes.map { RoundHole(strokes: $0) }
        if holes.isEmpty {
            holes = [RoundHole()]
        }
        round.holes = holes
        round.strokesVersion = snapshot.version
        rounds[i] = round
        return true
    }

    private func changeStroke(_ strokeID: UUID, in roundID: UUID, _ change: @escaping (inout Stroke) -> Void) {
        changeStrokes(roundID) { round in
            guard let holeIndex = round.holeIndex(containing: strokeID),
                  let strokeIndex = round.holes[holeIndex].strokes.firstIndex(where: { $0.id == strokeID }) else { return false }
            change(&round.holes[holeIndex].strokes[strokeIndex])
            return true
        }
    }

    /// Every stroke change adds 1 to the round's strokes version, so the watch can tell newer from older.
    private func changeStrokes(_ roundID: UUID, _ change: (inout Round) -> Bool) {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        var round = rounds[i]
        guard change(&round) else { return }
        round.strokesVersion += 1
        rounds[i] = round
        report(.strokesChanged(round))
    }

    // MARK: - Saving

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            rounds = try JSONDecoder().decode([Round].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return
        } catch {
            // Data saved by an older build can't be read and is thrown away
            Log.storage.error("Discarding saved rounds: \(String(describing: error), privacy: .public)")
            rounds = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(rounds)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.storage.error("Could not save rounds: \(String(describing: error), privacy: .public)")
        }
    }
}
