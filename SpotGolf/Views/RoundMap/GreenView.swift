import CourseDataSwift
import CoreLocation
import SwiftUI

/// The shown hole's green, drawn by the app so it can zoom in past the map's limit, for putts:
/// the green and the bunkers and water near it, the GPS track, the spots, the pin and the player,
/// with feet between the strokes. The spots are added, moved and opened here, and the pin can be
/// dragged. Unlike the map, a tap does not drop a target.
/// See plans/2026-10-17-green-view.md.
struct GreenView: View {
    let round: Round
    let shownHoleIndex: Int
    let trackLine: [CLLocationCoordinate2D]
    let holeTrack: [TrackPoint]
    /// The fixes where the hole could start, for the time of a spot placed by hand.
    let startWindow: [TrackPoint]
    let suggestions: [StrokeSuggestion]
    @Binding var spot: SpotSelection
    /// The X in the top bar.
    let close: () -> Void

    @Environment(PhoneServices.self) private var services
    @State private var projection: GreenProjection?
    /// Bunkers and water near the green.
    @State private var hazards: [Feature] = []
    /// The pinch's last magnification and the pan's last translation, to apply each change once.
    @State private var lastMagnification: CGFloat = 1
    @State private var lastPan: CGSize = .zero
    @State private var draggingStroke: Stroke?
    @State private var dragOffset: CGSize = .zero
    /// How far the dragged pin is from where it stands. Nil when it is not being dragged.
    @State private var pinOffset: CGSize?

    /// A dragged spot or pin lands this far above the finger, where a thumb does not hide it.
    private static let dropLift: CGFloat = 70
    /// Hazards with a corner this close to the green's center are drawn, in meters.
    private static let hazardReach: CLLocationDistance = 80
    private static let fringe = Color(red: 0.22, green: 0.42, blue: 0.18)
    private static let greenFill = Color(red: 0.42, green: 0.70, blue: 0.32)
    private static let sand = Color(red: 0.93, green: 0.86, blue: 0.66)
    private static let water = Color(red: 0.25, green: 0.50, blue: 0.80)

    private var location: CLLocation? {
        round.isActive ? services.locationManager.lastLocation : nil
    }

    private var strokes: [Stroke] {
        round.hole(at: shownHoleIndex).strokes
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ground
                .overlay(alignment: .topTrailing) {
                    pinDistance
                }
        }
        .onAppear(perform: loadHazards)
    }

    // MARK: - Top bar

    /// The title in the middle and the X on the right.
    private var topBar: some View {
        Text("Green View")
            .font(.headline)
            .accessibilityIdentifier("GreenViewTitle")
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Green View")
                .accessibilityIdentifier("CloseGreenView")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thickMaterial)
    }

    /// The feet to the pin in the box where the map shows the yards to it, during a round only.
    @ViewBuilder
    private var pinDistance: some View {
        if let feet = feetToPin {
            InformationBox(value: "\(feet)",
                           caption: round.hasKnownPin(holeIndex: shownHoleIndex) ? "ft to pin" : "ft to center",
                           identifier: "GreenViewPinDistance")
                .padding(.trailing, 12)
                .padding(.top, 12)
        }
    }

    /// Feet from the player to the pin, or to the green's center without one. Nil outside a round.
    private var feetToPin: Int? {
        guard let location, let pin = round.targetCoordinate(holeIndex: shownHoleIndex) else { return nil }
        return Self.feet(location.coordinate, pin)
    }

    private static func feet(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Int {
        Int((CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) * MapGeometry.feetPerMeter).rounded())
    }

    // MARK: - Ground

    private var ground: some View {
        ZStack {
            Canvas { context, _ in
                guard let projection else { return }
                drawGround(in: &context, projection)
            }
            .gesture(zoomTapGesture)
            .gesture(addSpotGesture)

            if let projection {
                markers(projection)
            }
        }
        .background(Self.fringe)
        .clipped()
        // Contains its markers, so they keep their own identifiers
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("GreenViewGround")
        .contentShape(Rectangle())
        .coordinateSpace(.named(Self.space))
        .simultaneousGesture(panGesture)
        .simultaneousGesture(pinchGesture)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if projection == nil, let green = round.green(holeIndex: shownHoleIndex) {
                projection = GreenProjection(green: green.polygon,
                                             heading: MapGeometry.heading(of: round, holeIndex: shownHoleIndex) ?? 0,
                                             size: size)
            } else {
                projection?.resize(to: size)
            }
        }
    }

    private static let space = "GreenViewSpace"

    private func loadHazards() {
        guard let center = round.greenCenter(holeIndex: shownHoleIndex) else { return }
        let middle = CLLocation(latitude: center.latitude, longitude: center.longitude)
        hazards = round.course.features.filter { feature in
            (feature.type == .bunker || feature.type == .water)
                && feature.polygon.contains { middle.distance(from: $0.clLocation) < Self.hazardReach }
        }
    }

    /// The hazards, the green, the track, and the lines between strokes.
    private func drawGround(in context: inout GraphicsContext, _ projection: GreenProjection) {
        func path(_ coordinates: [CLLocationCoordinate2D], closed: Bool) -> Path {
            var path = Path()
            path.addLines(coordinates.map(projection.point(for:)))
            if closed { path.closeSubpath() }
            return path
        }

        for hazard in hazards {
            context.fill(path(hazard.polygon.map(\.clCoordinate), closed: true),
                         with: .color(hazard.type == .water ? Self.water : Self.sand))
        }
        if let green = round.green(holeIndex: shownHoleIndex) {
            let outline = path(green.polygon.map(\.clCoordinate), closed: true)
            context.fill(outline, with: .color(Self.greenFill))
            context.stroke(outline, with: .color(.white.opacity(0.8)), lineWidth: 1)
        }
        if trackLine.count >= 2 {
            context.stroke(path(trackLine, closed: false), with: .color(.blue),
                           style: StrokeStyle(lineWidth: 1, lineCap: .butt, dash: [6, 4]))
        }
        for line in strokeLines {
            context.stroke(path(line.coordinates, closed: false), with: .color(.white), lineWidth: 1)
        }
    }

    private var strokeLines: [StrokeLine] {
        MapGeometry.strokeLines(strokes)
    }

    // MARK: - Markers

    @ViewBuilder
    private func markers(_ projection: GreenProjection) -> some View {
        ZStack {
            distanceLabels(projection)
            ForEach(MapGeometry.stacked(suggestions)) { suggestion in
                if let coordinate = suggestion.coordinate {
                    SuggestionPin(kind: suggestion.kind) {
                        SpotActions.takeSuggestion(suggestion, round: round, holeIndex: shownHoleIndex,
                                                   holeTrack: holeTrack, services: services, spot: &spot)
                    }
                    .standing(at: projection.point(for: coordinate))
                }
            }
            ForEach(Array(strokes.enumerated()), id: \.element.id) { index, stroke in
                spotMarker(index: index, stroke: stroke, projection: projection)
            }
            if let pin = round.pin(onHole: shownHoleIndex) {
                pinMarker(pin, projection: projection)
            }
            if let location {
                PlayerDot()
                    .position(projection.point(for: location.coordinate))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Feet on the middle of each line between strokes, always shown.
    private func distanceLabels(_ projection: GreenProjection) -> some View {
        ZStack {
            ForEach(strokeLines.indices, id: \.self) { index in
                DistanceLabel(value: strokeLines[index].feet, unit: .feet, identifier: "GreenStrokeDistance_\(index + 1)")
                    .fixedSize()
                    .position(projection.point(for: strokeLines[index].midpoint))
            }
        }
        .allowsHitTesting(false)
    }

    private func spotMarker(index: Int, stroke: Stroke, projection: GreenProjection) -> some View {
        let isDragging = draggingStroke?.id == stroke.id
        let dot = projection.point(for: stroke.coordinate)
        return SpotPin(number: index + 1, stroke: stroke, isDragging: isDragging) {
            spot.newIndex = index
            spot.stroke = stroke
        }
        .offset(isDragging ? dragOffset : .zero)
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
                .onChanged { value in
                    guard case .second(true, let drag) = value else { return }
                    if draggingStroke == nil {
                        withAnimation(.easeOut(duration: 0.15)) {
                            draggingStroke = stroke
                            dragOffset = CGSize(width: 0, height: -(PinMetrics.headCenter + Self.dropLift))
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    if let drag {
                        dragOffset = CGSize(width: drag.location.x - dot.x, height: drag.location.y - Self.dropLift - dot.y)
                    }
                }
                .onEnded { value in
                    if case .second(true, _) = value {
                        let drop = CGPoint(x: dot.x + dragOffset.width, y: dot.y + dragOffset.height)
                        SpotActions.move(stroke, to: projection.coordinate(at: drop), round: round,
                                         startWindow: startWindow, services: services)
                    }
                    draggingStroke = nil
                    dragOffset = .zero
                }
        )
        .standing(at: dot)
    }

    /// The flag, which can be dragged to move the pin. A drop off the green springs back.
    private func pinMarker(_ pin: PinLocation, projection: GreenProjection) -> some View {
        let base = projection.point(for: pin.coordinate)
        let offset = pinOffset ?? .zero
        return PinFlag(source: pin.source, scale: MapGeometry.flagScale(metersPerPoint: 1 / projection.pointsPerMeter),
                       raised: MapGeometry.hasPinsOnGreen(round, holeIndex: shownHoleIndex,
                                                          suggestions: suggestions))
            .overlay(alignment: .bottomLeading) {
                if pinOffset != nil {
                    // While dragged, a bullseye on the pole's base shows where the pin would land,
                    // as on a dragged spot
                    TargetMarker()
                        .frame(width: 0, height: 0)
                        .offset(x: PinFlag.poleWidth / 2)
                        .allowsHitTesting(false)
                }
            }
            // A larger area to grab than the thin pole
            .padding(Self.pinGrab)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        if pinOffset == nil {
                            withAnimation(.easeOut(duration: 0.15)) {
                                pinOffset = CGSize(width: 0, height: -Self.dropLift)
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        if let drag {
                            pinOffset = CGSize(width: drag.location.x - base.x, height: drag.location.y - Self.dropLift - base.y)
                        }
                    }
                    .onEnded { value in
                        guard case .second(true, _) = value, let pinOffset else {
                            pinOffset = nil
                            return
                        }
                        let drop = projection.coordinate(at: CGPoint(x: base.x + pinOffset.width, y: base.y + pinOffset.height))
                        if round.isOnGreen(drop, holeIndex: shownHoleIndex) {
                            services.roundStore.setPin(drop, holeIndex: shownHoleIndex, roundID: round.id)
                            self.pinOffset = nil
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            withAnimation(.spring(duration: 0.3)) {
                                self.pinOffset = nil
                            }
                        }
                    }
            )
            .accessibilityIdentifier("GreenViewPin")
            // The pole's base, inside the grab padding, on the pin
            .frame(width: 0, height: 0, alignment: .bottomLeading)
            .offset(x: offset.width - Self.pinGrab - PinFlag.poleWidth / 2, y: offset.height + Self.pinGrab)
            .position(base)
    }

    private static let pinGrab: CGFloat = 14

    // MARK: - Gestures

    /// Pans the ground, unless a spot or the pin is being dragged.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard draggingStroke == nil, pinOffset == nil else {
                    lastPan = value.translation
                    return
                }
                projection?.pan(by: CGSize(width: value.translation.width - lastPan.width,
                                           height: value.translation.height - lastPan.height))
                lastPan = value.translation
            }
            .onEnded { _ in lastPan = .zero }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                projection?.zoom(by: value.magnification / lastMagnification, at: value.startLocation)
                lastMagnification = value.magnification
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    /// A double tap zooms in 2x there.
    private var zoomTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in projection?.zoom(by: 2, at: value.location) }
    }

    /// A long press adds a spot there.
    private var addSpotGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { value in
                guard case .second(true, let drag) = value, let drag, let projection else { return }
                SpotActions.addSpot(at: projection.coordinate(at: drag.location), round: round, holeIndex: shownHoleIndex,
                                    startWindow: startWindow, services: services, spot: &spot)
            }
    }
}

/// The player on the green: a blue dot with a white ring, as on the map.
private struct PlayerDot: View {
    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 16, height: 16)
            .overlay { Circle().stroke(.white, lineWidth: 3) }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .accessibilityLabel("Your location")
    }
}

private extension View {
    /// Stands a pin on `point`: its bottom edge, which runs through its dot, on the point.
    func standing(at point: CGPoint) -> some View {
        fixedSize()
            .frame(width: 0, height: 0, alignment: .bottom)
            .position(point)
    }
}
