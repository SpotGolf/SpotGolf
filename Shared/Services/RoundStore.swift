import Foundation
import Observation
import os
import CoreLocation
import CourseDataSwift
import SwiftData

/// A change to the rounds, passed to every listener while the change is made.
enum RoundEvent {
    /// Any change to `rounds`, from either device.
    case roundsChanged
    /// A display hole change made on this device.
    case displayHoleChanged(Round)
    /// A pin set on this device.
    case pinsChanged(Round)
    /// A stroke change made on this device.
    case strokesChanged(Round)
}

/// Holds every round and saves it with SwiftData. Every change to a round goes through here.
/// Changes made on this device are reported to listeners as `RoundEvent`s so they can be sent
/// to the other device; changes applied from the other device are only reported as
/// `roundsChanged`.
@MainActor
@Observable
class RoundStore {
    /// Every round, newest first.
    private(set) var rounds: [Round] = []

    /// Adds 1 on every change to any round, so views can react to changes inside a round.
    private(set) var revision = 0

    @ObservationIgnored private let context: ModelContext

    // Run in the order added, during the change, so messages to the other device keep its order
    @ObservationIgnored private var listeners: [(RoundEvent) -> Void] = []

    init(context: ModelContext) {
        self.context = context
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

    /// Changes a round and saves. Does nothing for an unknown round.
    func update(_ id: UUID, _ change: (Round) -> Void) {
        guard let round = round(id) else { return }
        change(round)
        changed(round)
    }

    // MARK: - Rounds

    /// Adds a new round. An existing round with the same ID is returned unchanged.
    @discardableResult
    func startRound(id: UUID = UUID(), date: Date = Date(), courseSelection: CourseSelection,
                    status: RoundStatus = .active) -> Round {
        if let existing = round(id) { return existing }
        let round = Round(id: id, date: date, status: status, courseSelection: courseSelection)
        add(round)
        return round
    }

    /// Adds a round made elsewhere, such as one read from an export.
    func add(_ round: Round) {
        guard self.round(round.id) == nil else { return }
        context.insert(round)
        // Newest first: a round from an export or iCloud can be older than the others
        rounds.insert(round, at: rounds.firstIndex { $0.date < round.date } ?? rounds.count)
        changed()
    }

    /// Changes a round to match its copy from iCloud. Unlike `update`, it keeps the
    /// `changedAt` the change sets, since the change was not made on this phone.
    func replace(_ id: UUID, _ change: (Round) -> Void) {
        guard let round = round(id) else { return }
        change(round)
        changed()
    }

    func deleteRound(_ id: UUID) {
        guard let round = round(id) else { return }
        context.delete(round)
        rounds.removeAll { $0.id == id }
        changed()
    }

    // MARK: - Display hole

    /// Shows a hole on both devices. The active round when `roundID` is nil.
    func setDisplayHole(_ index: Int, roundID: UUID? = nil, at date: Date = Date()) {
        guard let id = roundID ?? activeRound?.id, let round = round(id),
              round.setDisplayHole(index, at: date) else { return }
        changed(round)
        report(.displayHoleChanged(round))
    }

    /// Takes the other device's display hole when it is newer. Returns true if it changed.
    @discardableResult
    func mergeDisplayHole(_ displayHole: DisplayHole, roundID: UUID) -> Bool {
        guard let round = round(roundID), round.mergeDisplayHole(displayHole) else { return false }
        changed(round)
        return true
    }

    // MARK: - Pins

    /// Sets the pin on a hole, in the active round when `roundID` is nil. Does nothing when the
    /// point is not on that hole's green.
    func setPin(_ coordinate: CLLocationCoordinate2D, holeIndex: Int, roundID: UUID? = nil, at date: Date = Date()) {
        guard let id = roundID ?? activeRound?.id, let round = round(id),
              round.setPin(coordinate, onHole: holeIndex, at: date) else { return }
        changed(round)
        report(.pinsChanged(round))
    }

    /// Gives every hole with a green and no pin a pin at the green's center, when a round starts
    /// or resumes. Reported like a pin set here, so the other device gets them too.
    func addCenterPins(roundID: UUID) {
        changePins(roundID) { $0.addCenterPins() }
    }

    /// Adds other golfers' pins, by the merge rules. Reported like a pin set here, so the other
    /// device gets them too.
    func addSharedPins(_ pins: [PinLocation?], roundID: UUID) {
        changePins(roundID) { $0.mergePins(pins) }
    }

    private func changePins(_ roundID: UUID, _ change: (Round) -> Bool) {
        guard let round = round(roundID), change(round) else { return }
        changed(round)
        report(.pinsChanged(round))
    }

    /// Takes the other device's pins that replace this one's. Returns true if any changed.
    @discardableResult
    func mergePins(_ pins: [PinLocation?], roundID: UUID) -> Bool {
        guard let round = round(roundID), round.mergePins(pins) else { return false }
        changed(round)
        return true
    }

    // MARK: - Strokes

    /// Adds a stroke. When its `hitAt` is known, a hole's first stroke starts the hole in the
    /// timeline, and an earlier one added later moves the start back.
    func addStroke(to roundID: UUID, holeIndex: Int, stroke: Stroke) {
        var added = false
        changeStrokes(roundID) { round in
            guard !round.hasStroke(id: stroke.id) else { return false }
            round.addStroke(stroke, toHoleIndex: holeIndex)
            added = true
            return true
        }
        guard added, let hitAt = stroke.hitAt, let round = round(roundID),
              round.strokeHit(onHole: holeIndex, at: hitAt) else { return }
        changed(round)
    }

    /// Moves a stroke. A manual stroke was hit where it is now, so `estimatedTime` works out its
    /// time again, from the GPS, and its hole's start follows it both ways. A stroke from a
    /// suggestion keeps the suggestion's time, so its hole's start stays.
    func moveStroke(_ stroke: Stroke, to coordinate: CLLocationCoordinate2D, in roundID: UUID,
                    estimatedTime: (Stroke) -> Date? = { _ in nil }) {
        guard let round = round(roundID), let holeIndex = round.holeIndex(containing: stroke.id),
              let existing = round.holes[holeIndex].strokes.first(where: { $0.id == stroke.id }) else { return }
        var moved = Stroke(id: existing.id, coordinate: coordinate, penaltyStrokes: existing.penaltyStrokes,
                           quality: existing.quality, club: existing.club, origin: existing.origin, hitAt: existing.hitAt)
        if moved.origin == .manual {
            moved.hitAt = estimatedTime(moved)
        }
        let replacement = moved
        changeStroke(stroke.id, in: roundID) { $0 = replacement }
        guard replacement.origin == .manual else { return }
        let movedBack = replacement.hitAt.map { round.strokeHit(onHole: holeIndex, at: $0) } ?? false
        let restarted = round.restartHole(holeIndex) { $0.hitAt ?? estimatedTime($0) }
        if movedBack || restarted {
            changed(round)
        }
    }

    /// Sets the stroke's penalty strokes, kept between 0 and `Stroke.maxPenaltyStrokes`.
    func setPenaltyStrokes(_ count: Int, strokeID: UUID, in roundID: UUID) {
        changeStroke(strokeID, in: roundID) { $0.penaltyStrokes = Stroke.clamped(penaltyStrokes: count) }
    }

    func setShotQuality(_ quality: ShotQuality, strokeID: UUID, in roundID: UUID) {
        changeStroke(strokeID, in: roundID) { $0.quality = quality }
    }

    func setStrokeClub(strokeID: UUID, club: Club?, in roundID: UUID) {
        changeStroke(strokeID, in: roundID) { $0.clubID = club?.id }
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

    /// Removes a stroke. Its hole's start follows the strokes left (see `Round.restartHole`), and
    /// `estimatedTime` works out the time of a manual stroke that has none, from the GPS. A stroke
    /// from a suggestion shows the suggestion again.
    func removeStroke(_ stroke: Stroke, from roundID: UUID, estimatedTime: (Stroke) -> Date? = { _ in nil }) {
        var removedFrom: Int?
        changeStrokes(roundID) { round in
            guard let holeIndex = round.holeIndex(containing: stroke.id) else { return false }
            round.holes[holeIndex].strokes.removeAll { $0.id == stroke.id }
            removedFrom = holeIndex
            return true
        }
        guard let removedFrom, let round = round(roundID),
              round.restartHole(removedFrom, hitTime: { $0.hitAt ?? estimatedTime($0) }) else { return }
        changed(round)
    }

    /// Applies the phone's strokes on the watch when the snapshot is newer than the last one applied.
    @discardableResult
    func applyStrokes(_ snapshot: StrokesSnapshot) -> Bool {
        guard let round = round(snapshot.roundID), snapshot.version > round.strokesVersion else { return false }
        var holes = snapshot.holes.map { RoundHole(strokes: $0) }
        if holes.isEmpty {
            holes = [RoundHole()]
        }
        round.holes = holes
        round.updateStats()
        round.strokesVersion = snapshot.version
        changed(round)
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

    /// Every stroke change adds 1 to the round's strokes version, so the watch can tell newer from
    /// older, and saves the holes' stats again.
    private func changeStrokes(_ roundID: UUID, _ change: (Round) -> Bool) {
        guard let round = round(roundID), change(round) else { return }
        round.updateStats()
        round.strokesVersion += 1
        changed(round)
        report(.strokesChanged(round))
    }

    // MARK: - Saving

    private func load() {
        let newestFirst = FetchDescriptor<Round>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        do {
            rounds = try context.fetch(newestFirst)
            // Rounds saved before stats were get them once
            let missing = rounds.filter(\.needsStats)
            missing.forEach { $0.updateStats() }
            if !missing.isEmpty {
                try context.save()
            }
        } catch {
            Log.storage.error("Could not load rounds: \(String(describing: error))")
        }
    }

    /// Saves, and tells views and listeners that a round changed. `round`, when given, is the
    /// round changed on this phone, which takes the time as its `changedAt`.
    private func changed(_ round: Round? = nil) {
        round?.changedAt = Date()
        do {
            try context.save()
        } catch {
            Log.storage.error("Could not save rounds: \(String(describing: error))")
        }
        revision += 1
        report(.roundsChanged)
    }
}
