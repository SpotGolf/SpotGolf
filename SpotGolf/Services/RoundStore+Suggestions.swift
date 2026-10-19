import Foundation

extension RoundStore {
    /// Turns a stroke suggestion into a stroke on hole `holeIndex`, hit at the suggestion's time,
    /// in the order it was probably hit, going by the hole's GPS. The suggestion is hidden while
    /// the stroke exists. The club is guessed for the stroke's place in that order. Returns the
    /// stroke, or nil when the suggestion has no location.
    @discardableResult
    func addSuggestedStroke(_ suggestion: StrokeSuggestion, holeIndex: Int, roundID: UUID, holeTrack: [TrackPoint],
                            bag: GolfBag) -> Stroke? {
        guard let coordinate = suggestion.coordinate, let round = round(roundID) else { return nil }
        // Both worked out before the add, so they describe the strokes the new one joins
        let strokes = round.hole(at: holeIndex).strokes
        let insertAt = Self.insertionIndex(for: suggestion.timestamp, in: strokes, holeTrack: holeTrack)
        let club = HoleOverview.guessedClub(round, holeIndex: holeIndex, strokeIndex: insertAt, at: coordinate, bag: bag)
        let stroke = Stroke(coordinate: coordinate, club: club, origin: .suggestion(id: suggestion.id),
                            hitAt: suggestion.timestamp)
        addStroke(to: roundID, holeIndex: holeIndex, stroke: stroke)
        if insertAt != strokes.count {
            reorderStroke(stroke, to: insertAt, in: roundID)
        }
        return stroke
    }

    /// Where a stroke hit at `timestamp` goes among a hole's strokes: before the first one that
    /// was probably hit later, going by the hole's GPS.
    static func insertionIndex(for timestamp: Date, in strokes: [Stroke], holeTrack: [TrackPoint]) -> Int {
        strokes.firstIndex { stroke in
            StrokeFinder.estimatedTime(of: stroke, in: holeTrack).map { timestamp < $0 } ?? false
        } ?? strokes.count
    }
}
