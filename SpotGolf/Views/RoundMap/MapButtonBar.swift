import SwiftUI

/// Edit at the bottom left, the map buttons at the right, and setting the pin in the middle.
struct MapButtonBar: View {
    let round: Round
    let shownHoleIndex: Int
    @Binding var isEditing: Bool
    @Binding var showHoleTimes: Bool
    let followsUserLocation: Bool
    /// The location button: the camera goes back to following the player.
    let followUserLocation: () -> Void

    @Environment(PhoneServices.self) private var services

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                isEditing.toggle()
            } label: {
                Image(systemName: isEditing ? "checkmark" : "square.and.pencil")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(12)
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

    /// Hole times (only while editing), and following the player's location (only during a round).
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
                .padding(14)
                .background(.thickMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }

            if round.isActive {
                Button(action: followUserLocation) {
                    Image(systemName: followsUserLocation ? "location.fill" : "location")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .padding(14)
                        .background(.thickMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }
            }
        }
    }
}
