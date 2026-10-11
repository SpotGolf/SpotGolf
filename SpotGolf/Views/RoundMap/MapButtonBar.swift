import SwiftUI

/// Edit at the bottom left, the map buttons at the right, and setting the pin in the middle.
struct MapButtonBar: View {
    let round: Round
    let shownHoleIndex: Int
    @Binding var isEditing: Bool
    @Binding var showHoleTimes: Bool
    @Binding var showLog: Bool
    let followsUserLocation: Bool
    /// The location button: the camera goes back to following the player.
    let followUserLocation: () -> Void
    let mapStyle: MapStyleChoice
    /// The map button: opens the sheet that picks the map's style.
    let pickMapStyle: () -> Void

    @Environment(PhoneServices.self) private var services

    /// Every round button is this big, as Apple Maps' are.
    private static let buttonSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                isEditing.toggle()
            } label: {
                Image(systemName: isEditing ? "checkmark" : "square.and.pencil")
                    .font(.title3)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .background(.thickMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .accessibilityLabel(isEditing ? "Done" : "Edit")
            .accessibilityIdentifier("EditHole")

            Spacer(minLength: 0)

            mapButtons
        }
        .overlay(alignment: .bottom) {
            setPinButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    /// Shown only during a round, while the phone is on the shown hole's green: saves where the
    /// player stands as the hole's pin, as the watch's button does.
    @ViewBuilder
    private var setPinButton: some View {
        if round.isActive, !isEditing, let location = services.locationManager.lastLocation,
           round.isOnGreen(location.coordinate, holeIndex: shownHoleIndex) {
            Button {
                services.roundStore.setPin(location.coordinate, holeIndex: shownHoleIndex, roundID: round.id)
            } label: {
                Label("Set pin location", systemImage: "flag.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.thickMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .accessibilityIdentifier("SetPinLocation")
        }
    }

    /// Hole times and the round's log (only while editing), then the map's style and, during a
    /// round, following the player's location, together in one capsule as Apple Maps has them.
    private var mapButtons: some View {
        VStack(spacing: 8) {
            if isEditing {
                Button {
                    showHoleTimes = true
                } label: {
                    Image(systemName: "clock")
                }
                .accessibilityLabel("Hole times")
                .font(.title3)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(.thickMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                Button {
                    showLog = true
                } label: {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel("Log")
                .accessibilityIdentifier("RoundLog")
                .font(.title3)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(.thickMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }

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
}
