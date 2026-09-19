import Foundation

@MainActor
class GuessStore: ObservableObject {
    @Published private(set) var guesses: [UUID: [MissedMarkGuess]] = [:] // keyed by round ID

    static let maxPerHole = 10

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("guesses.json")
    }

    init() {
        load()
    }

    func guesses(for roundID: UUID, holeIndex: Int) -> [MissedMarkGuess] {
        (guesses[roundID] ?? []).filter { $0.holeIndex == holeIndex }
    }

    func add(_ guess: MissedMarkGuess) {
        var roundGuesses = guesses[guess.roundID] ?? []

        // Check duplicate
        guard !roundGuesses.contains(where: { $0.id == guess.id }) else { return }

        // Cap per hole
        let holeCount = roundGuesses.filter { $0.holeIndex == guess.holeIndex }.count
        guard holeCount < Self.maxPerHole else { return }

        roundGuesses.append(guess)
        guesses[guess.roundID] = roundGuesses
        save()
    }

    func remove(guessID: UUID, roundID: UUID) {
        guesses[roundID]?.removeAll { $0.id == guessID }
        if guesses[roundID]?.isEmpty == true {
            guesses.removeValue(forKey: roundID)
        }
        save()
    }

    func clearHole(roundID: UUID, holeIndex: Int) {
        guesses[roundID]?.removeAll { $0.holeIndex == holeIndex }
        if guesses[roundID]?.isEmpty == true {
            guesses.removeValue(forKey: roundID)
        }
        save()
    }

    func deleteRound(_ roundID: UUID) {
        guesses.removeValue(forKey: roundID)
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            guesses = try JSONDecoder().decode([UUID: [MissedMarkGuess]].self, from: data)
        } catch {
            print("Failed to load guesses: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(guesses)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save guesses: \(error)")
        }
    }
}
