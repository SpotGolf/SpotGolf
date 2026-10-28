import SwiftUI

/// Green View over the ruler at the bottom left, the map buttons at the right, and in the middle
/// the suggestion pins' legend, with setting the pin above it. Green View hides both capsules,
/// and its X closes it.
struct MapButtonBar: View {
    let round: Round
    let shownHoleIndex: Int
    /// The ruler button: shows and hides the lines and distances between the hole's strokes.
    @Binding var showsStrokeLines: Bool
    let followsUserLocation: Bool
    /// The location button: the camera goes back to following the player.
    let followUserLocation: () -> Void
    let mapStyle: MapStyleChoice
    /// The map button: opens the sheet that picks the map's style.
    let pickMapStyle: () -> Void
    /// Green View is showing in place of the map, so the map's own buttons are hidden.
    let showsGreenView: Bool
    /// The Green View button. Nil when the hole has no green outline to draw.
    let openGreenView: (() -> Void)?

    @Environment(PhoneServices.self) private var services

    /// Every round button is this big, as Apple Maps' are.
    private static let buttonSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // One capsule, as the map buttons on the right. Not in Green View, which closes with its X.
            if !showsGreenView {
                leftCapsule
            }

            Spacer(minLength: 0)

            mapButtons
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                setPinButton
                SuggestionLegend()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    /// Green View over the ruler, in one capsule.
    private var leftCapsule: some View {
        VStack(spacing: 0) {
            if let openGreenView {
                Button(action: openGreenView) {
                    Image(systemName: "flag")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                }
                .accessibilityLabel("Green View")
                .accessibilityIdentifier("GreenView")
            }

            Button {
                showsStrokeLines.toggle()
            } label: {
                Image(systemName: "ruler")
                    .font(.title3)
                    .foregroundStyle(showsStrokeLines ? Color.blue : Color.secondary)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
            }
            .accessibilityLabel("Distances")
            .accessibilityAddTraits(showsStrokeLines ? .isSelected : [])
            .accessibilityIdentifier("StrokeLines")
        }
        .background(.thickMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    /// Shown only during a round, while the phone is on the shown hole's green: saves where the
    /// player stands as the hole's pin, as the watch's button does. Red until the player has set
    /// the pin, then blue and offering to update it.
    @ViewBuilder
    private var setPinButton: some View {
        if round.isActive, let location = services.locationManager.lastLocation,
           round.isOnGreen(location.coordinate, holeIndex: shownHoleIndex) {
            let isSet = round.hasSetPin(holeIndex: shownHoleIndex)
            Button {
                services.roundStore.setPin(location.coordinate, holeIndex: shownHoleIndex, roundID: round.id)
            } label: {
                Label(isSet ? "Update pin" : "Set pin location", systemImage: "flag.fill")
                    .font(.headline)
                    .foregroundStyle(isSet ? .blue : .red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.thickMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .accessibilityIdentifier("SetPinLocation")
        }
    }

    /// The map's style and, during a round, following the player's location, together in one
    /// capsule as Apple Maps has them. Not in Green View.
    @ViewBuilder
    private var mapButtons: some View {
        if !showsGreenView {
            mapCapsule
        }
    }

    private var mapCapsule: some View {
        VStack(spacing: 0) {
            Button(action: pickMapStyle) {
                Image(systemName: mapStyle.symbolName)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
            }
            .accessibilityLabel("Map style")
            .accessibilityValue(Text(mapStyle.title))
            .accessibilityIdentifier("MapStyle")

            if round.isActive {
                Button(action: followUserLocation) {
                    Image(systemName: followsUserLocation ? "location.fill" : "location")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                }
                .accessibilityLabel("Follow location")
            }
        }
        .background(.thickMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}
