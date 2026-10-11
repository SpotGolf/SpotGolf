import SwiftUI

/// Moves a spot in its hole's order, picks its club, counts its penalty strokes, rates the shot,
/// or deletes it. The club grid shows the bag with the stroke's club selected, or the guess for a
/// stroke without one. Save applies every change at once; Cancel drops them.
/// See plans/2026-10-11-club-selection.md and plans/2026-10-11-penalty-strokes.md.
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

                    ClubGrid(clubs: offeredClubs, isSelected: { $0 == spot.club }, compact: true) { club in
                        spot.club = club
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Penalty strokes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                counterButton("minus", "Remove a penalty stroke", isEnabled: spot.penaltyStrokes > 0) {
                                    spot.penaltyStrokes -= 1
                                }
                                .accessibilityIdentifier("PenaltyMinus")
                                Text("\(spot.penaltyStrokes)")
                                    .font(.title3)
                                    .monospacedDigit()
                                    .frame(minWidth: 24)
                                    .accessibilityLabel("Penalty strokes")
                                    .accessibilityValue("\(spot.penaltyStrokes)")
                                    .accessibilityIdentifier("PenaltyStrokes")
                                counterButton("plus", "Add a penalty stroke",
                                              isEnabled: spot.penaltyStrokes < Stroke.maxPenaltyStrokes) {
                                    spot.penaltyStrokes += 1
                                }
                                .accessibilityIdentifier("PenaltyPlus")
                            }
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Shot quality")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                qualitySegment(.bad, "Bad shot") { Image(systemName: "hand.thumbsdown") }
                                qualitySegment(.okay, "Okay shot") { NeutralFace() }
                                qualitySegment(.good, "Good shot") { Image(systemName: "hand.thumbsup") }
                            }
                            .padding(2)
                            .background(Capsule().fill(Color(.systemFill)))
                        }
                    }

                    Button("Delete Spot", role: .destructive) {
                        spot.confirmsDelete = true
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if let stroke = spot.stroke {
                    spot.club = initialClub(of: stroke)
                    spot.penaltyStrokes = stroke.penaltyStrokes
                    spot.quality = stroke.quality
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

    /// A round button on one side of the penalty counter, disabled at the counter's end.
    private func counterButton(_ systemImage: String, _ title: LocalizedStringKey, isEnabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(!isEnabled)
    }

    /// One segment of the shot quality pill. Selects the quality; a rating cannot be cleared.
    private func qualitySegment<Icon: View>(_ quality: ShotQuality, _ title: LocalizedStringKey,
                                            @ViewBuilder icon: () -> Icon) -> some View {
        let isSelected = spot.quality == quality
        let icon = icon()
        return Button {
            spot.quality = quality
        } label: {
            icon
                .font(.title3)
                .foregroundStyle(isSelected ? Color.white : .primary)
                .frame(width: 44, height: 30)
                .background(Capsule().fill(isSelected ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("Quality-\(quality.rawValue)")
    }

    /// Applies the sheet's club, penalty strokes, shot quality and order to the stroke.
    private func save(_ stroke: Stroke) {
        if spot.club != stroke.club {
            services.roundStore.setStrokeClub(strokeID: stroke.id, club: spot.club, in: round.id)
        }
        if spot.penaltyStrokes != stroke.penaltyStrokes {
            services.roundStore.setPenaltyStrokes(spot.penaltyStrokes, strokeID: stroke.id, in: round.id)
        }
        if spot.quality != stroke.quality {
            services.roundStore.setShotQuality(spot.quality, strokeID: stroke.id, in: round.id)
        }
        services.roundStore.reorderStroke(stroke, to: spot.newIndex, in: round.id)
    }
}

/// A flat neutral face for the "okay" shot quality, drawn to match the outline thumbs symbols
/// beside it: a circle with two eyes and a straight mouth.
private struct NeutralFace: View {
    private let size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(lineWidth: size * 0.08)
            HStack(spacing: size * 0.2) {
                Circle().frame(width: size * 0.13, height: size * 0.13)
                Circle().frame(width: size * 0.13, height: size * 0.13)
            }
            .offset(y: -size * 0.14)
            Capsule()
                .frame(width: size * 0.42, height: size * 0.08)
                .offset(y: size * 0.2)
        }
        .frame(width: size, height: size)
    }
}
