import MapKit
import SwiftUI

/// Where the round map looks, and how it is zoomed.
struct MapCameraState {
    var position: MapCameraPosition = .userLocation(fallback: .automatic)
    /// The camera follows the player until the map is moved away from them.
    var followsUserLocation = true
    /// The map has moved to the hole once, after the first location or straight away for a past round.
    var hasInitialPan = false
    /// Counts camera moves, so things drawn over the map redraw as it moves.
    var changes = 0
    /// The map's size, and how many meters one point of it covers, to keep gaps a fixed size on screen.
    var mapSize: CGSize = .zero
    var metersPerPoint: Double = 0.5
}

/// The spot being edited in the spot sheet.
struct SpotSelection {
    var stroke: Stroke?
    /// Where the spot goes in its hole's order.
    var newIndex = 0
    /// The delete confirmation is showing.
    var confirmsDelete = false
}
