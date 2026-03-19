import Foundation
import CoreLocation
import CourseData

@MainActor
class RoundStore: ObservableObject {
    @Published var rounds: [Round] = []

    var onSyncEvent: ((SyncMessage) -> Void)?

    var activeRound: Round? {
        rounds.first(where: { $0.isActive })
    }

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("rounds.json")
    }

    init() {
        load()
    }

    func startRound(id: UUID = UUID(), date: Date = Date(), fromSync: Bool = false) {
        // End any existing active round
        if let index = rounds.firstIndex(where: { $0.isActive }) {
            rounds[index].end()
        }
        // If the round already exists (e.g. reactivation from the other device), reactivate it
        if let index = rounds.firstIndex(where: { $0.id == id }) {
            rounds[index].isActive = true
            save()
            if !fromSync {
                onSyncEvent?(.startRound(id, rounds[index].date))
            }
            return
        }
        let round = Round(id: id, date: date)
        rounds.insert(round, at: 0)
        save()
        if !fromSync {
            onSyncEvent?(.startRound(id, date))
        }
    }

    func endRound(roundID: UUID? = nil, fromSync: Bool = false) {
        let predicate: (Round) -> Bool = if let roundID {
            { $0.id == roundID }
        } else {
            { $0.isActive }
        }
        if let index = rounds.firstIndex(where: predicate) {
            let id = rounds[index].id
            rounds[index].end()
            save()
            if !fromSync {
                onSyncEvent?(.endRound(id))
            }
        }
    }

    func addMark(_ mark: BallMark, fromSync: Bool = false) {
        if let index = rounds.firstIndex(where: { $0.isActive }) {
            let roundID = rounds[index].id
            let holeIndex = rounds[index].currentHoleIndex
            rounds[index].addMark(mark)
            save()
            if !fromSync {
                onSyncEvent?(.addMark(mark, holeIndex, roundID))
            }
        }
    }

    func addMark(to roundID: UUID, holeIndex: Int, mark: BallMark, fromSync: Bool = false) {
        if let index = rounds.firstIndex(where: { $0.id == roundID }) {
            rounds[index].addMark(mark, toHoleIndex: holeIndex)
            save()
            if !fromSync {
                onSyncEvent?(.addMark(mark, holeIndex, roundID))
            }
        }
    }

    func nextHole(roundID: UUID? = nil) {
        let predicate: (Round) -> Bool = if let roundID {
            { $0.id == roundID }
        } else {
            { $0.isActive }
        }
        if let index = rounds.firstIndex(where: predicate) {
            guard rounds[index].nextHole() else { return }
            save()
        }
    }

    func previousHole(roundID: UUID? = nil) {
        let predicate: (Round) -> Bool = if let roundID {
            { $0.id == roundID }
        } else {
            { $0.isActive }
        }
        if let index = rounds.firstIndex(where: predicate) {
            guard rounds[index].previousHole() else { return }
            save()
        }
    }

    func setHoleIndex(_ index: Int, roundID: UUID? = nil) {
        let predicate: (Round) -> Bool = if let roundID {
            { $0.id == roundID }
        } else {
            { $0.isActive }
        }
        if let i = rounds.firstIndex(where: predicate) {
            while rounds[i].holes.count <= index && rounds[i].holes.count < Round.maxHoles {
                rounds[i].holes.append(RoundHole())
            }
            let clamped = min(index, rounds[i].holes.count - 1)
            guard clamped != rounds[i].currentHoleIndex else { return }
            rounds[i].currentHoleIndex = clamped
            save()
        }
    }

    func setCourse(_ selection: CourseSelection, for roundID: UUID? = nil, fromSync: Bool = false) {
        let predicate: (Round) -> Bool = if let roundID {
            { $0.id == roundID }
        } else {
            { $0.isActive }
        }
        if let index = rounds.firstIndex(where: predicate) {
            let id = rounds[index].id
            rounds[index].courseSelection = selection
            save()
            if !fromSync {
                onSyncEvent?(.setCourse(selection, id))
            }
        }
    }

    func moveMark(_ mark: BallMark, to coordinate: CLLocationCoordinate2D, in roundID: UUID) {
        if let roundIndex = rounds.firstIndex(where: { $0.id == roundID }),
           let holeIndex = rounds[roundIndex].holeIndex(containing: mark.id),
           let markIndex = rounds[roundIndex].holes[holeIndex].marks.firstIndex(where: { $0.id == mark.id }) {
            let updated = BallMark(id: mark.id, coordinate: coordinate, timestamp: mark.timestamp, type: mark.type)
            rounds[roundIndex].holes[holeIndex].marks[markIndex] = updated
            save()
        }
    }

    func setMarkType(markID: UUID, type: BallMarkType, in roundID: UUID, fromSync: Bool = false) {
        if let roundIndex = rounds.firstIndex(where: { $0.id == roundID }),
           let holeIndex = rounds[roundIndex].holeIndex(containing: markID),
           let markIndex = rounds[roundIndex].holes[holeIndex].marks.firstIndex(where: { $0.id == markID }) {
            rounds[roundIndex].holes[holeIndex].marks[markIndex].type = type
            save()
            if !fromSync {
                onSyncEvent?(.setMarkType(markID, type, roundID))
            }
        }
    }

    func reorderMark(_ mark: BallMark, to newIndex: Int, in roundID: UUID) {
        if let roundIndex = rounds.firstIndex(where: { $0.id == roundID }),
           let holeIndex = rounds[roundIndex].holeIndex(containing: mark.id),
           let markIndex = rounds[roundIndex].holes[holeIndex].marks.firstIndex(where: { $0.id == mark.id }) {
            let clamped = min(max(newIndex, 0), rounds[roundIndex].holes[holeIndex].marks.count - 1)
            let removed = rounds[roundIndex].holes[holeIndex].marks.remove(at: markIndex)
            rounds[roundIndex].holes[holeIndex].marks.insert(removed, at: clamped)
            save()
        }
    }

    func removeMark(_ mark: BallMark, from roundID: UUID) {
        if let index = rounds.firstIndex(where: { $0.id == roundID }),
           let holeIndex = rounds[index].holeIndex(containing: mark.id) {
            rounds[index].holes[holeIndex].marks.removeAll { $0.id == mark.id }
            save()
        }
    }

    func reactivateRound(_ roundID: UUID, fromSync: Bool = false) {
        guard activeRound == nil,
              let index = rounds.firstIndex(where: { $0.id == roundID }) else { return }
        rounds[index].isActive = true
        save()
        if !fromSync {
            onSyncEvent?(.startRound(roundID, rounds[index].date))
        }
    }

    func deleteRound(_ round: Round) {
        rounds.removeAll { $0.id == round.id }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            rounds = try JSONDecoder().decode([Round].self, from: data)
        } catch {
            print("Failed to load rounds: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(rounds)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save rounds: \(error)")
        }
    }
}
