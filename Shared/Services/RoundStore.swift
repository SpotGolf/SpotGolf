import Foundation
import CoreLocation
import CourseDataSwift

/// Holds and saves every round. Changes made on this device are reported through
/// `onTimelineChanged` and `onMarksChanged` so they can be sent to the other device;
/// changes applied from the other device are not reported.
@MainActor
class RoundStore: ObservableObject {
    @Published var rounds: [Round] = [] {
        didSet { save() }
    }

    /// A hole change or timeline correction made on this device.
    var onTimelineChanged: ((Round) -> Void)?

    /// A mark change made on this device.
    var onMarksChanged: ((Round) -> Void)?

    private let fileURL: URL

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent("rounds.json")
        load()
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

    // MARK: - Holes

    /// Moves play to a later hole. Earlier holes can't be played again, so a lower hole is ignored.
    func startHole(_ index: Int, roundID: UUID? = nil, at date: Date = Date(), source: HoleStartSource) {
        guard let id = roundID ?? activeRound?.id,
              let i = rounds.firstIndex(where: { $0.id == id }) else { return }
        var round = rounds[i]
        guard round.startHole(index, at: date, source: source) else { return }
        rounds[i] = round
        onTimelineChanged?(round)
    }

    /// Merges the other device's timeline. Returns true if anything changed.
    @discardableResult
    func mergeTimeline(_ entries: [HoleStart], roundID: UUID) -> Bool {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return false }
        var round = rounds[i]
        guard round.mergeTimeline(entries) else { return false }
        rounds[i] = round
        return true
    }

    /// Replaces the timeline with a corrected one made on this device.
    func setTimeline(_ entries: [HoleStart], roundID: UUID) {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        let normalized = HoleTimeline.normalized(entries)
        guard normalized != rounds[i].holeTimeline else { return }
        var round = rounds[i]
        round.holeTimeline = normalized
        round.ensureHole(round.currentHoleIndex)
        rounds[i] = round
        onTimelineChanged?(round)
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

    // MARK: - Marks

    func addMark(to roundID: UUID, holeIndex: Int, mark: BallMark) {
        changeMarks(roundID) { round in
            guard !round.hasMark(id: mark.id) else { return false }
            round.addMark(mark, toHoleIndex: holeIndex)
            return true
        }
    }

    func moveMark(_ mark: BallMark, to coordinate: CLLocationCoordinate2D, in roundID: UUID) {
        changeMark(mark.id, in: roundID) { existing in
            existing = BallMark(id: existing.id, coordinate: coordinate, timestamp: existing.timestamp, type: existing.type)
        }
    }

    func setMarkType(markID: UUID, type: BallMarkType, in roundID: UUID) {
        changeMark(markID, in: roundID) { $0.type = type }
    }

    func reorderMark(_ mark: BallMark, to newIndex: Int, in roundID: UUID) {
        changeMarks(roundID) { round in
            guard let holeIndex = round.holeIndex(containing: mark.id),
                  let markIndex = round.holes[holeIndex].marks.firstIndex(where: { $0.id == mark.id }) else { return false }
            let clamped = min(max(newIndex, 0), round.holes[holeIndex].marks.count - 1)
            guard clamped != markIndex else { return false }
            let removed = round.holes[holeIndex].marks.remove(at: markIndex)
            round.holes[holeIndex].marks.insert(removed, at: clamped)
            return true
        }
    }

    func removeMark(_ mark: BallMark, from roundID: UUID) {
        changeMarks(roundID) { round in
            guard let holeIndex = round.holeIndex(containing: mark.id) else { return false }
            round.holes[holeIndex].marks.removeAll { $0.id == mark.id }
            return true
        }
    }

    /// Applies the phone's marks on the watch when the snapshot is newer than the last one applied.
    @discardableResult
    func applyMarks(_ snapshot: MarksSnapshot) -> Bool {
        guard let i = rounds.firstIndex(where: { $0.id == snapshot.roundID }),
              snapshot.version > rounds[i].marksVersion else { return false }
        var round = rounds[i]
        var holes = snapshot.holes.map { RoundHole(marks: $0) }
        if holes.isEmpty {
            holes = [RoundHole()]
        }
        round.holes = holes
        round.ensureHole(round.currentHoleIndex)
        round.marksVersion = snapshot.version
        rounds[i] = round
        return true
    }

    private func changeMark(_ markID: UUID, in roundID: UUID, _ change: @escaping (inout BallMark) -> Void) {
        changeMarks(roundID) { round in
            guard let holeIndex = round.holeIndex(containing: markID),
                  let markIndex = round.holes[holeIndex].marks.firstIndex(where: { $0.id == markID }) else { return false }
            change(&round.holes[holeIndex].marks[markIndex])
            return true
        }
    }

    /// Every mark change adds 1 to the round's marks version, so the watch can tell newer from older.
    private func changeMarks(_ roundID: UUID, _ change: (inout Round) -> Bool) {
        guard let i = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        var round = rounds[i]
        guard change(&round) else { return }
        round.marksVersion += 1
        rounds[i] = round
        onMarksChanged?(round)
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
            print("Discarding saved rounds: \(error)")
            rounds = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(rounds)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save rounds: \(error)")
        }
    }
}
