import SwiftUI

/// Moves a spot in its hole's order, changes its type, or deletes it.
struct SpotEditSheet: View {
    let round: Round
    let shownHoleIndex: Int
    @Binding var spot: SpotSelection

    @Environment(PhoneServices.self) private var services

    /// The strokes in the spot's hole, or in the shown hole without a spot.
    private var strokeCount: Int {
        guard let stroke = spot.stroke, let holeIndex = round.holeIndex(containing: stroke.id) else {
            return round.hole(at: shownHoleIndex).strokes.count
        }
        return round.holes[holeIndex].strokes.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Stepper("Spot: \(spot.newIndex + 1)", value: $spot.newIndex, in: 0...(max(strokeCount - 1, 0)))
                    .font(.title3)
                    .padding(.horizontal)

                if let stroke = spot.stroke {
                    Divider()

                    if stroke.type == .regular {
                        Button {
                            setType(.penalty, of: stroke)
                        } label: {
                            Label("Penalty stroke", systemImage: "exclamationmark.triangle.fill")
                        }
                        .tint(.red)
                        .accessibilityIdentifier("StrokePenalty")

                        Button {
                            setType(.outOfBounds, of: stroke)
                        } label: {
                            Label("Out of bounds", systemImage: "xmark.circle.fill")
                        }
                        .accessibilityIdentifier("StrokeOutOfBounds")
                    } else {
                        Button {
                            setType(.regular, of: stroke)
                        } label: {
                            Label("Clear penalty", systemImage: "arrow.uturn.backward.circle")
                        }
                        .accessibilityIdentifier("ClearPenalty")
                    }
                }

                Button("Delete Spot", role: .destructive) {
                    spot.confirmsDelete = true
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Edit Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        spot.stroke = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let stroke = spot.stroke {
                            services.roundStore.reorderStroke(stroke, to: spot.newIndex, in: round.id)
                        }
                        spot.stroke = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func setType(_ type: StrokeType, of stroke: Stroke) {
        services.roundStore.setStrokeType(strokeID: stroke.id, type: type, in: round.id)
        spot.stroke = nil
    }
}
