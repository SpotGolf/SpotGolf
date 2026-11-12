import Foundation

/// What the Caddie's outcome capsule and stats sheet say about the shot on the map. See
/// plans/2026-11-11-shot-dispersion.md, section 6.
struct CaddieStats: Equatable {
    let club: Club
    /// The club's Caddie average: the yards to the aim point.
    let yards: Int
    let outcomes: DispersionOutcomes
    /// 95% of shots stop within this many yards left or right of the aim line. Nil until the
    /// shape is worked out.
    let lateral: Int?
    /// 95% of shots stop between these yards along the aim line.
    let downrange: ClosedRange<Int>?
    /// The aim point is on the green, so the capsule counts shots on the green alone.
    let aimsAtGreen: Bool

    init(shot: CaddieShot, outcomes: DispersionOutcomes, aimsAtGreen: Bool) {
        club = shot.club
        yards = shot.yards
        self.outcomes = outcomes
        lateral = shot.shape.map { Int($0.lateral.rounded()) }
        downrange = shot.shape.map { Int($0.downrange.lowerBound.rounded())...Int($0.downrange.upperBound.rounded()) }
        self.aimsAtGreen = aimsAtGreen
    }

    static func percent(_ share: Double) -> Int {
        Int((share * 100).rounded())
    }

    /// The capsule's text, such as "52% fairway · 6% hazard".
    var summary: String {
        let hazard = Self.percent(outcomes.hazard)
        return aimsAtGreen
            ? String(localized: "\(Self.percent(outcomes.green))% green · \(hazard)% hazard")
            : String(localized: "\(Self.percent(outcomes.fairwayOrGreen))% fairway · \(hazard)% hazard")
    }

    /// What VoiceOver reads for the capsule.
    var spokenSummary: String {
        let hazard = Self.percent(outcomes.hazard)
        return aimsAtGreen
            ? String(localized: "Caddie: \(club.name), \(Self.percent(outcomes.green))% green, \(hazard)% hazard")
            : String(localized: "Caddie: \(club.name), \(Self.percent(outcomes.fairwayOrGreen))% fairway or green, \(hazard)% hazard")
    }
}
