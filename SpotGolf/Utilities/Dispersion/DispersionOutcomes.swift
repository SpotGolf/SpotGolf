import Foundation
import simd

/// The chance of a shot stopping on each lie. See plans/2026-11-11-shot-dispersion.md, section 4.
struct DispersionOutcomes: Equatable, Sendable {
    var fairway = 0.0
    var rough = 0.0
    var sand = 0.0
    var water = 0.0
    var green = 0.0

    var fairwayOrGreen: Double { fairway + green }
    /// The course data has no out of bounds, so sand and water are the hazards.
    var hazard: Double { sand + water }

    /// The share of `shots`, in shot-local yards from `start` along `heading`, that stop on each
    /// lie. `start` is on the plane of `lies`, and `heading` in radians counter-clockwise from
    /// east.
    init(shots: some Collection<SIMD2<Double>>, start: GroundPoint, heading: Double, lies: LieGrid) {
        guard !shots.isEmpty else { return }
        let meters = 0.9144
        let along = GroundPoint(x: cos(heading), y: sin(heading))
        let right = GroundPoint(x: sin(heading), y: -cos(heading))
        let each = 1 / Double(shots.count)
        for shot in shots {
            switch lies.lie(at: start + along * (shot.y * meters) + right * (shot.x * meters)) {
            case .fairway: fairway += each
            case .rough: rough += each
            case .sand: sand += each
            case .water: water += each
            case .green: green += each
            }
        }
    }
}
