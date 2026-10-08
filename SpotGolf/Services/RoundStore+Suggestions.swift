import Foundation

extension RoundStore {
    /// Turns a stroke suggestion into a stroke on hole `holeIndex`, in the order it was
    /// probably hit, going by the hole's GPS, and hides the suggestion.
    func addSuggestedStroke(_ suggestion: StrokeSuggestion, holeIndex: Int, roundID: UUID, holeTrack: [TrackPoint]) {
        guard let coordinate = suggestion.coordinate, let round = round(roundID) else { return }
        let stroke = Stroke(coordinate: coordinate)
        // Both worked out before the add, so they describe the strokes the new one joins
        let strokes = round.hole(at: holeIndex).strokes
        let insertAt = Self.insertionIndex(for: suggestion.timestamp, in: strokes, holeTrack: holeTrack)
        addStroke(to: roundID, holeIndex: holeIndex, stroke: stroke, hitAt: suggestion.timestamp)
        if insertAt != strokes.count {
            reorderStroke(stroke, to: insertAt, in: roundID)
        }
        hideSuggestion(suggestion.id, roundID: roundID)
    }

    /// Where a stroke hit at `timestamp` goes among a hole's strokes: before the first one that
    /// was probably hit later, going by the hole's GPS.
    static func insertionIndex(for timestamp: Date, in strokes: [Stroke], holeTrack: [TrackPoint]) -> Int {
        strokes.firstIndex { stroke in
            StrokeFinder.estimatedTime(of: stroke, in: holeTrack).map { timestamp < $0 } ?? false
        } ?? strokes.count
    }
}
