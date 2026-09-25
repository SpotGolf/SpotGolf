import Foundation

/// Swing guesses on the phone, per round. Removed guesses are remembered, so the same swing
/// never brings a guess back.
@MainActor
class GuessStore: ObservableObject {
    @Published private(set) var guesses: [UUID: [MissedMarkGuess]] = [:] // keyed by round ID
    private var removed: [UUID: Set<UUID>] = [:]

    static let maxPerHole = 10

    private let fileURL: URL

    private struct Saved: Codable {
        var guesses: [UUID: [MissedMarkGuess]]
        var removed: [UUID: Set<UUID>]
    }

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent("guesses.json")
        load()
    }

    func guesses(for roundID: UUID) -> [MissedMarkGuess] {
        guesses[roundID] ?? []
    }

    /// The round's guesses whose time falls on `holeIndex` in its timeline.
    func guesses(for round: Round, holeIndex: Int) -> [MissedMarkGuess] {
        guesses(for: round.id).filter { round.holeIndex(at: $0.timestamp) == holeIndex }
    }

    /// Adds a guess unless it is already there, was removed, or its hole already has `maxPerHole`.
    @discardableResult
    func add(_ guess: MissedMarkGuess, in round: Round) -> Bool {
        var roundGuesses = guesses[guess.roundID] ?? []
        guard !roundGuesses.contains(where: { $0.id == guess.id }),
              removed[guess.roundID]?.contains(guess.id) != true,
              guesses(for: round, holeIndex: round.holeIndex(at: guess.timestamp)).count < Self.maxPerHole else { return false }
        roundGuesses.append(guess)
        guesses[guess.roundID] = roundGuesses
        save()
        return true
    }

    func remove(guessID: UUID, roundID: UUID) {
        guesses[roundID]?.removeAll { $0.id == guessID }
        if guesses[roundID]?.isEmpty == true {
            guesses.removeValue(forKey: roundID)
        }
        removed[roundID, default: []].insert(guessID)
        save()
    }

    func deleteRound(_ roundID: UUID) {
        guesses.removeValue(forKey: roundID)
        removed.removeValue(forKey: roundID)
        save()
    }

    private func load() {
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: fileURL))
            guesses = saved.guesses
            removed = saved.removed
        } catch CocoaError.fileReadNoSuchFile {
            return
        } catch {
            print("Discarding saved guesses: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(Saved(guesses: guesses, removed: removed))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save guesses: \(error)")
        }
    }
}
