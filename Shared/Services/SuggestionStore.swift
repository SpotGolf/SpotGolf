import Foundation

/// Phone: the stroke suggestions the user dismissed or turned into strokes, per round.
/// Suggestions themselves are not saved: `StrokeFinder` works them out again when a hole is
/// shown, and gives the same stop the same ID, so a hidden suggestion stays hidden.
@MainActor
class SuggestionStore: ObservableObject {
    @Published private(set) var hidden: [UUID: Set<UUID>] = [:] // keyed by round ID

    private let fileURL: URL

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent("suggestions.json")
        load()
    }

    func hiddenIDs(for roundID: UUID) -> Set<UUID> {
        hidden[roundID] ?? []
    }

    /// Hides a suggestion the user dismissed or turned into a stroke.
    func hide(_ suggestionID: UUID, roundID: UUID) {
        guard hidden[roundID]?.contains(suggestionID) != true else { return }
        hidden[roundID, default: []].insert(suggestionID)
        save()
    }

    func deleteRound(_ roundID: UUID) {
        guard hidden.removeValue(forKey: roundID) != nil else { return }
        save()
    }

    private func load() {
        do {
            hidden = try JSONDecoder().decode([UUID: Set<UUID>].self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            return
        } catch {
            print("Discarding saved suggestions: \(error)")
        }
    }

    private func save() {
        do {
            try JSONEncoder().encode(hidden).write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save suggestions: \(error)")
        }
    }
}
