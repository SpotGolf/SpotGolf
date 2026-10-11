import MapKit
import SwiftUI

/// Where the round map looks, and how it is zoomed.
struct MapCameraState {
    var position: MapCameraPosition = .userLocation(fallback: .automatic)
    /// The camera follows the player until the map is moved away from them.
    var followsUserLocation = true
    /// The camera last pointed at the player while following. The map being off it by more than
    /// a GPS fix's drift means the user panned, zoomed or turned it.
    var followCamera: MapCamera?
    /// The map has settled on `followCamera`. Until then it is still on its way there, so a
    /// camera that differs from it is the move itself, not the user's.
    var isAtFollowCamera = false
    /// The map has moved to the hole once, after the first location or straight away for a past round.
    var hasInitialPan = false
    /// Counts camera moves, so things drawn over the map redraw as it moves.
    var changes = 0
    /// The map's size, and how many meters one point of it covers, to keep gaps a fixed size on screen.
    var mapSize: CGSize = .zero
    var metersPerPoint: Double = 0.5

    /// Points the camera at the player and follows them from here on.
    mutating func follow(_ location: CLLocation, heading: Double?) {
        let camera = MapGeometry.following(location, heading: heading)
        followsUserLocation = true
        followCamera = camera
        isAtFollowCamera = false
        position = .camera(camera)
    }

    /// Shows a hole, no longer following the player.
    mutating func show(_ holeCamera: MapCamera) {
        followsUserLocation = false
        followCamera = nil
        isAtFollowCamera = false
        position = .camera(holeCamera)
    }

    /// Takes in a camera the map passed through or stopped at. Once the map has reached the
    /// player, any camera off them is the user's and ends following. Before it has, only the
    /// camera it stops at counts: a stop off the player means the user cut the move short.
    mutating func mapMoved(to camera: MapCamera, ended: Bool) {
        guard followsUserLocation, let followCamera else { return }
        let movedAway = MapGeometry.isMovedAway(camera, from: followCamera)
        if movedAway && (ended || isAtFollowCamera) {
            followsUserLocation = false
        } else if ended {
            isAtFollowCamera = true
        }
    }
}

/// The spot being edited in the spot sheet.
struct SpotSelection {
    var stroke: Stroke?
    /// Where the spot goes in its hole's order.
    var newIndex = 0
    /// The club picked in the sheet: the stroke's, or the guess for a stroke without one.
    var club: Club?
    /// The penalty strokes counted in the sheet.
    var penaltyStrokes = 0
    /// The shot quality picked in the sheet.
    var quality: ShotQuality = .good
    /// The delete confirmation is showing.
    var confirmsDelete = false
}
