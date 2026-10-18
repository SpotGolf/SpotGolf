import CoreLocation

/// The edits the round map and Green View both make to a hole's spots, so a spot added or a
/// suggestion taken on either is the same.
@MainActor
enum SpotActions {
    /// Adds a spot at `coordinate`, after the hole's other strokes, and opens it in the spot sheet.
    /// Its club is guessed, and it was hit when the player was nearest to it, going by the hole's GPS.
    static func addSpot(at coordinate: CLLocationCoordinate2D, round: Round, holeIndex: Int, holeTrack: [TrackPoint],
                        services: PhoneServices, spot: inout SpotSelection) {
        spot.newIndex = round.hole(at: holeIndex).strokes.count // capture before append
        let stroke = Stroke(coordinate: coordinate,
                            club: HoleOverview.guessedClub(round, holeIndex: holeIndex, strokeIndex: spot.newIndex,
                                                           at: coordinate, bag: services.golfBag.bag))
        services.roundStore.addStroke(to: round.id, holeIndex: holeIndex, stroke: stroke,
                                      hitAt: StrokeFinder.estimatedTime(of: stroke, in: holeTrack))
        spot.stroke = stroke
    }

    /// Turns a suggestion into a real stroke and opens it in the spot sheet.
    static func takeSuggestion(_ suggestion: StrokeSuggestion, round: Round, holeIndex: Int, holeTrack: [TrackPoint],
                               services: PhoneServices, spot: inout SpotSelection) {
        guard let stroke = services.roundStore.addSuggestedStroke(
            suggestion, holeIndex: holeIndex, roundID: round.id, holeTrack: holeTrack,
            bag: services.golfBag.bag) else { return }
        spot.newIndex = round.hole(at: holeIndex).strokes.firstIndex { $0.id == stroke.id } ?? 0
        spot.stroke = stroke
    }
}
