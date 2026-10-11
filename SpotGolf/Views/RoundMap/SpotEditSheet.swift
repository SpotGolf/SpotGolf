import SwiftUI

/// Moves a spot in its hole's order, picks its club, marks it a penalty or out of bounds, or
/// deletes it. The club grid shows the bag with the stroke's club selected, or the guess for a
/// stroke without one. Save applies every change at once; Cancel drops them.
/// See plans/2026-10-11-club-selection.md.
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

    /// The bag, plus the stroke's club when the bag no longer has it.
    private var offeredClubs: [Club] {
        let bag = services.golfBag.bag
        let own = spot.stroke?.club
        return Club.all.filter { bag.contains($0) || $0 == own }
    }

    /// The stroke's club, or the guess for its spot.
    private func initialClub(of stroke: Stroke) -> Club? {
        if let club = stroke.club { return club }
        let holeIndex = round.holeIndex(containing: stroke.id) ?? shownHoleIndex
        let strokeIndex = round.hole(at: holeIndex).strokes.firstIndex { $0.id == stroke.id } ?? spot.newIndex
        return HoleOverview.guessedClub(round, holeIndex: holeIndex, strokeIndex: strokeIndex, at: stroke.coordinate,
                                        bag: services.golfBag.bag)
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Sized to fit, or the stepper's capsule draws below the frame it is centered by
                    HStack(spacing: 16) {
                        Text("Spot: \(spot.newIndex + 1)")
                            .font(.title3)
                        Stepper("Spot", value: $spot.newIndex, in: 0...(max(strokeCount - 1, 0)))
                            .labelsHidden()
                            .fixedSize()
                    }

                    Divider()

                    ClubGrid(clubs: offeredClubs, isSelected: { $0 == spot.club }) { club in
                        spot.club = club
                    }

                    Divider()

                    HStack(spacing: 8) {
                        typeButton(.penalty, "Penalty stroke", systemImage: "exclamationmark.triangle.fill")
                            .accessibilityIdentifier("StrokePenalty")
                        typeButton(.outOfBounds, "Out of bounds", systemImage: "xmark.circle.fill")
                            .accessibilityIdentifier("StrokeOutOfBounds")
                    }

                    Button("Delete Spot", role: .destructive) {
                        spot.confirmsDelete = true
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.top, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if let stroke = spot.stroke {
                    spot.club = initialClub(of: stroke)
                    spot.type = stroke.type
                }
            }
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
                            save(stroke)
                        }
                        spot.stroke = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Selects the type, or clears it back to a regular stroke when it is already selected.
    private func typeButton(_ type: StrokeType, _ title: LocalizedStringKey, systemImage: String) -> some View {
        ChoiceButton(isSelected: spot.type == type) {
            spot.type = spot.type == type ? .regular : type
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    /// Applies the sheet's club, type and order to the stroke.
    private func save(_ stroke: Stroke) {
        if spot.club != stroke.club {
            services.roundStore.setStrokeClub(strokeID: stroke.id, club: spot.club, in: round.id)
        }
        if spot.type != stroke.type {
            services.roundStore.setStrokeType(strokeID: stroke.id, type: spot.type, in: round.id)
        }
        services.roundStore.reorderStroke(stroke, to: spot.newIndex, in: round.id)
    }
}
