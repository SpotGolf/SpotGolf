import CoreLocation
import SwiftUI

/// The distances over the top of the map during a round: the hole's on the right, and the
/// tapped point's on the left with the button that clears it. A past round has none, since
/// they come from the player's location.
struct MapInfoOverlay: View {
    let round: Round
    let shownHoleIndex: Int
    @Binding var target: CLLocationCoordinate2D?

    @Environment(PhoneServices.self) private var services

    private var location: CLLocation? { services.locationManager.lastLocation }

    var body: some View {
        if round.isActive {
            HStack(alignment: .top) {
                if target != nil {
                    targetInformation
                }
                Spacer()
                keyInformation
            }
        }
    }

    private var pinCaption: Bool { round.hasKnownPin(holeIndex: shownHoleIndex) }

    private var keyInformation: some View {
        let yards = HoleOverview.yardsToPin(round, holeIndex: shownHoleIndex, from: location)
        let feet = HoleOverview.feetToGreenCenter(round, holeIndex: shownHoleIndex, from: location)
        return VStack(spacing: 8) {
            InformationBox(value: yards.map(String.init) ?? "—",
                           caption: pinCaption ? "yds to pin" : "yds to center",
                           identifier: "DistanceToCenter")
            InformationBox(value: feet.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "—",
                           caption: "ft elevation",
                           identifier: "ElevationChange")
        }
        .padding(.trailing, 12)
        .padding(.top, 12)
    }

    /// The tapped point's yards from the player and to the green, with the button that clears it
    /// underneath. On the left, opposite the hole's key information.
    private var targetInformation: some View {
        let targetLocation = target.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let toGreen = HoleOverview.yardsToPin(round, holeIndex: shownHoleIndex, from: targetLocation)
        let toTarget = targetLocation.flatMap { target in
            location.map { Int(DistanceCalculator.yards(from: $0, to: target)) }
        }
        return VStack(spacing: 8) {
            InformationBox(value: toGreen.map(String.init) ?? "—",
                           caption: pinCaption ? "To pin" : "To green",
                           identifier: "TargetToGreen")
            InformationBox(value: toTarget.map(String.init) ?? "—",
                           caption: "To point",
                           identifier: "DistanceToTarget")
            Button {
                target = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
                    .padding(14)
                    .background(.thickMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .accessibilityLabel("Clear target")
            .accessibilityIdentifier("ClearTarget")
        }
        .padding(.leading, 12)
        .padding(.top, 12)
    }
}

/// A number with its caption under it, in a small box over the map.
private struct InformationBox: View {
    let value: String
    let caption: String
    let identifier: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 84)
        .padding(.vertical, 8)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
