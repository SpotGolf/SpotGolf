import CoreLocation

/// The edits the round map and Green View both make to a hole's spots, so a spot added or a
/// suggestion taken on either is the same.
@MainActor
enum SpotActions {
    /// Adds a spot at `coordinate`, after the hole's other strokes, and opens it in the spot sheet.
    /// Its club is guessed, and it was hit when the player was nearest to it, going by the GPS in
    /// the hole's `startWindow`.
    static func addSpot(at coordinate: CLLocationCoordinate2D, round: Round, holeIndex: Int, startWindow: [TrackPoint],
                        services: PhoneServices, spot: inout SpotSelection) {
        spot.newIndex = round.hole(at: holeIndex).strokes.count // capture before append
        var stroke = Stroke(coordinate: coordinate,
                            club: HoleOverview.guessedClub(round, holeIndex: holeIndex, strokeIndex: spot.newIndex,
                                                           at: coordinate, bag: services.golfBag.bag))
        stroke.hitAt = StrokeFinder.estimatedTime(of: stroke, in: startWindow)
        services.roundStore.addStroke(to: round.id, holeIndex: holeIndex, stroke: stroke)
        spot.stroke = stroke
        spot.isNew = true
    }

    /// Adds a tap in, for a short putt the watch did not hear or the group gave: a putt
    /// `MapGeometry.tapInMeters` past the pin, on the line from the hole's last stroke, as if that
    /// putt rolled by. It is not opened in the spot sheet, so one tap adds it.
    static func addTapIn(round: Round, holeIndex: Int, startWindow: [TrackPoint], services: PhoneServices) {
        guard let pin = round.targetCoordinate(holeIndex: holeIndex) else { return }
        let coordinate = MapGeometry.tapInCoordinate(pin: pin, previous: round.hole(at: holeIndex).strokes.last?.coordinate,
                                                     heading: MapGeometry.heading(of: round, holeIndex: holeIndex) ?? 0)
        var stroke = Stroke(coordinate: coordinate, club: services.golfBag.bag.clubs.first { $0.kind == .putter })
        stroke.hitAt = StrokeFinder.estimatedTime(of: stroke, in: startWindow)
        services.roundStore.addStroke(to: round.id, holeIndex: holeIndex, stroke: stroke)
    }

    /// Turns a suggestion into a real stroke and opens it in the spot sheet.
    static func takeSuggestion(_ suggestion: StrokeSuggestion, round: Round, holeIndex: Int, holeTrack: [TrackPoint],
                               services: PhoneServices, spot: inout SpotSelection) {
        guard let stroke = services.roundStore.addSuggestedStroke(
            suggestion, holeIndex: holeIndex, roundID: round.id, holeTrack: holeTrack,
            bag: services.golfBag.bag) else { return }
        spot.newIndex = round.hole(at: holeIndex).strokes.firstIndex { $0.id == stroke.id } ?? 0
        spot.stroke = stroke
        spot.isNew = true
    }

    /// Closes the spot sheet without saving. A stroke added to open it is taken back out, and the
    /// suggestion it came from shows again.
    static func cancel(round: Round, startWindow: [TrackPoint], services: PhoneServices, spot: inout SpotSelection) {
        if spot.isNew, let stroke = spot.stroke {
            remove(stroke, round: round, startWindow: startWindow, services: services)
        }
        spot.close()
    }

    /// Removes a stroke. Its hole's start follows the strokes left, and a manual stroke with no
    /// time gets one from the GPS in the hole's `startWindow`.
    static func remove(_ stroke: Stroke, round: Round, startWindow: [TrackPoint], services: PhoneServices) {
        services.roundStore.removeStroke(stroke, from: round.id) { StrokeFinder.estimatedTime(of: $0, in: startWindow) }
    }

    /// Moves a stroke. A manual stroke gets its time again from the GPS in the hole's
    /// `startWindow`, and its hole's start follows it.
    static func move(_ stroke: Stroke, to coordinate: CLLocationCoordinate2D, round: Round, startWindow: [TrackPoint],
                     services: PhoneServices) {
        services.roundStore.moveStroke(stroke, to: coordinate, in: round.id) {
            StrokeFinder.estimatedTime(of: $0, in: startWindow)
        }
    }
}
