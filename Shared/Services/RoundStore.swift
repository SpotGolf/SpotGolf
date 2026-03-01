import Foundation
import CoreLocation

@MainActor
class RoundStore: ObservableObject {
    @Published var rounds: [Round] = []

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

    func startRound() {
        // End any existing active round
        if let index = rounds.firstIndex(where: { $0.isActive }) {
            rounds[index].end()
        }
        let round = Round()
        rounds.insert(round, at: 0)
        save()
    }

    func endRound() {
        if let index = rounds.firstIndex(where: { $0.isActive }) {
            rounds[index].end()
            save()
        }
    }

    func addMark(_ mark: BallMark) {
        if let index = rounds.firstIndex(where: { $0.isActive }) {
            rounds[index].addMark(mark)
            save()
        }
    }

    func addMark(to roundID: UUID, mark: BallMark) {
        if let index = rounds.firstIndex(where: { $0.id == roundID }) {
            rounds[index].addMark(mark)
            save()
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
