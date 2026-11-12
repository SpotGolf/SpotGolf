import Foundation

extension RoundStore {
    /// Turns a stroke suggestion into a stroke on hole `holeIndex`, hit at the suggestion's time,
    /// after the hole's other strokes. Where the player walked has no say in its order: a chip
    /// hit back towards the tee is still the next stroke. The suggestion is hidden while the
    /// stroke exists. The club is guessed for the stroke's place in the hole. Returns the stroke,
    /// or nil when the suggestion has no location.
    @discardableResult
    func addSuggestedStroke(_ suggestion: StrokeSuggestion, holeIndex: Int, roundID: UUID, bag: GolfBag) -> Stroke? {
        guard let coordinate = suggestion.coordinate, let round = round(roundID) else { return nil }
        // Worked out before the add, so it describes the strokes the new one joins
        let club = HoleOverview.guessedClub(round, holeIndex: holeIndex, strokeIndex: round.hole(at: holeIndex).strokes.count,
                                            at: coordinate, bag: bag)
        let stroke = Stroke(coordinate: coordinate, club: club, origin: .suggestion(id: suggestion.id),
                            hitAt: suggestion.timestamp)
        addStroke(to: roundID, holeIndex: holeIndex, stroke: stroke)
        return stroke
    }
}
