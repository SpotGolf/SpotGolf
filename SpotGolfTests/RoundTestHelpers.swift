@testable import SpotGolf

extension Round {
    /// The play indexes of the holes with a start, in order.
    var startedHoles: [Int] {
        holeStarts.indices.filter { holeStarts[$0] != nil }
    }

    /// Pins by play index, as `pins` holds them, with only the holes given.
    func pinsByHole(_ entries: [Int: PinLocation]) -> [PinLocation?] {
        pins.indices.map { entries[$0] }
    }
}
