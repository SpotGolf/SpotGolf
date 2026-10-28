import MapKit
import SwiftUI

/// The map of the shown hole: the player, the pin, the spots, the GPS track, the tapped target
/// and its lines, hazard distances, stroke suggestions, and the lines between the hole's strokes
/// with the yards along each when they are turned on. Tapping a spot opens it, a long press adds
/// a spot, and a spot can be lifted and dragged to move it.
struct RoundMapLayer: View {
    let round: Round
    let shownHoleIndex: Int
    let showsStrokeLines: Bool
    /// Set while a spot is being dragged, so the map holds its hole.
    @Binding var isDraggingSpot: Bool
    /// The hole's track as the map draws it, and all of its fixes.
    let trackLine: [CLLocationCoordinate2D]
    let holeTrack: [TrackPoint]
    /// The fixes where the hole could start, for the time of a spot placed by hand.
    let startWindow: [TrackPoint]
    let suggestions: [StrokeSuggestion]
    let mapStyle: MapStyleChoice
    @Binding var camera: MapCameraState
    @Binding var target: CLLocationCoordinate2D?
    @Binding var spot: SpotSelection

    @Environment(PhoneServices.self) private var services
    @State private var draggingStroke: Stroke?
    @State private var dragOffset: CGSize = .zero
    /// A dragged spot lands this far above the finger, where a thumb does not hide it.
    private static let dropLift: CGFloat = 70

    var body: some View {
        let strokesToShow = round.hole(at: shownHoleIndex).strokes
        MapReader { proxy in
            let targetLines = targetLines
            let strokeLines = showsStrokeLines ? MapGeometry.strokeLines(strokesToShow) : []
            Map(position: $camera.position) {
                if round.isActive {
                    UserAnnotation()
                }
                if trackLine.count >= 2 {
                    MapPolyline(coordinates: trackLine)
                        .stroke(Color.blue,
                                style: StrokeStyle(lineWidth: 1, lineCap: .butt, dash: [6, 4]))
                }
                ForEach(targetLines.indices, id: \.self) { index in
                    MapPolyline(coordinates: targetLines[index])
                        .stroke(.white, style: StrokeStyle(lineWidth: 1, lineCap: .butt))
                }
                ForEach(strokeLines.indices, id: \.self) { index in
                    MapPolyline(coordinates: strokeLines[index].coordinates)
                        .stroke(.white, style: StrokeStyle(lineWidth: 1, lineCap: .butt))
                }
                if let target {
                    Annotation("", coordinate: target, anchor: .center) {
                        TargetMarker()
                    }
                }
                // Later annotations are drawn over earlier ones: suggestions, then strokes in the
                // order they were hit, then the flag
                ForEach(MapGeometry.stacked(suggestions)) { suggestion in
                    if let coordinate = suggestion.coordinate {
                        Annotation("", coordinate: coordinate, anchor: .bottom) {
                            SuggestionPin(kind: suggestion.kind) {
                                SpotActions.takeSuggestion(suggestion, round: round, holeIndex: shownHoleIndex,
                                                           holeTrack: holeTrack, services: services, spot: &spot)
                            }
                        }
                    }
                }
                ForEach(Array(strokesToShow.enumerated()), id: \.element.id) { index, stroke in
                    // The dot under the pin sits on the stroke
                    Annotation("", coordinate: stroke.coordinate, anchor: .bottom) {
                        spotMarker(index: index, stroke: stroke, proxy: proxy)
                    }
                }
                if let pin = round.pin(onHole: shownHoleIndex) {
                    // Last, so the flag is drawn over the spots and suggestions, not under them.
                    // The base of the pole sits on the pin. Taps on the pole go through to a pin
                    // under it.
                    Annotation("", coordinate: pin.coordinate, anchor: PinFlag.base) {
                        PinFlag(source: pin.source, scale: MapGeometry.flagScale(metersPerPoint: camera.metersPerPoint),
                                raised: MapGeometry.hasPinsOnGreen(round, holeIndex: shownHoleIndex,
                                                                   suggestions: suggestions))
                            .allowsHitTesting(false)
                    }
                }
            }
            .mapStyle(mapStyle.mapStyle)
            .mapControls {
                MapCompass()
            }
            .overlay {
                hazardBubbles(proxy: proxy)
            }
            .overlay {
                distanceLabels(strokeLines, proxy: proxy)
            }
            .onMapCameraChange(frequency: .continuous) { context in
                camera.changes &+= 1
                let metersAcross = context.rect.size.width / MKMapPointsPerMeterAtLatitude(context.region.center.latitude)
                if let metersPerPoint = MapGeometry.metersPerPoint(mapSize: camera.mapSize, heading: context.camera.heading,
                                                                   metersAcross: metersAcross) {
                    camera.metersPerPoint = metersPerPoint
                }
                // Ends following as soon as the user starts to move the map, so the next GPS fix
                // does not pull it back mid-gesture
                camera.mapMoved(to: context.camera, ended: false)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { camera.mapSize = $0 }
            .onMapCameraChange(frequency: .onEnd) { context in
                camera.mapMoved(to: context.camera, ended: true)
            }
            .onTapGesture(coordinateSpace: .local) { point in
                // Distances come from the player's location
                guard round.isActive,
                      let coordinate = proxy.convert(point, from: .local) else { return }
                target = coordinate
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag):
                            guard let drag,
                                  let coordinate = proxy.convert(drag.location, from: .global) else { return }
                            SpotActions.addSpot(at: coordinate, round: round, holeIndex: shownHoleIndex,
                                                startWindow: startWindow, services: services, spot: &spot)
                        default:
                            break
                        }
                    }
            )
        }
    }

    private func spotMarker(index: Int, stroke: Stroke, proxy: MapProxy) -> some View {
        SpotPin(number: index + 1, stroke: stroke, isDragging: draggingStroke?.id == stroke.id) {
            if let holeIdx = round.holeIndex(containing: stroke.id),
               let strokeIdx = round.holes[holeIdx].strokes.firstIndex(where: { $0.id == stroke.id }) {
                spot.newIndex = strokeIdx
            }
            spot.stroke = stroke
        }
        .offset(draggingStroke?.id == stroke.id ? dragOffset : .zero)
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                // The drag reports from the first movement, so the pin tracks the finger at once
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        if draggingStroke == nil {
                            withAnimation(.easeOut(duration: 0.15)) {
                                draggingStroke = stroke
                                isDraggingSpot = true
                                // The finger is on the head, so the spot rises to the drop point
                                // above it before the finger moves
                                dragOffset = CGSize(width: 0, height: -(PinMetrics.headCenter + Self.dropLift))
                            }
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                        }
                        if let drag, let dot = proxy.convert(stroke.coordinate, to: .global) {
                            // Puts the pin's dot on the drop point
                            let drop = dropPoint(under: drag)
                            dragOffset = CGSize(width: drop.x - dot.x, height: drop.y - dot.y)
                        }
                    default:
                        break
                    }
                }
                .onEnded { value in
                    switch value {
                    case .second(true, _):
                        // Lands where the pin's dot is shown, which is above the finger even
                        // when the finger never moved
                        if let dot = proxy.convert(stroke.coordinate, to: .global),
                           let coordinate = proxy.convert(CGPoint(x: dot.x + dragOffset.width,
                                                                  y: dot.y + dragOffset.height), from: .global) {
                            SpotActions.move(stroke, to: coordinate, round: round, startWindow: startWindow,
                                             services: services)
                        }
                    default:
                        break
                    }
                    draggingStroke = nil
                    isDraggingSpot = false
                    dragOffset = .zero
                }
        )
    }

    /// Where a dragged spot lands: above the finger, in global coordinates.
    private func dropPoint(under drag: DragGesture.Value) -> CGPoint {
        CGPoint(x: drag.location.x, y: drag.location.y - Self.dropLift)
    }

    /// The bubbles are drawn over the map rather than as map annotations, because an annotation
    /// swallows touches and would block a long press that adds a stroke underneath it.
    private func hazardBubbles(proxy: MapProxy) -> some View {
        // Reading the counter redraws the bubbles as the camera moves
        _ = camera.changes
        let hazards = HoleOverview.hazardsAhead(round, holeIndex: shownHoleIndex,
                                                from: services.locationManager.lastLocation)
        return ZStack {
            ForEach(hazards) { hazard in
                if let point = proxy.convert(hazard.nearestPoint.clCoordinate, to: .local) {
                    HazardBubble(yards: hazard.distanceYards)
                        .fixedSize()
                        .frame(width: 0, height: 0, alignment: .bottom)
                        .position(point)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
    }

    /// The yards along each stroke line, on its middle. Drawn over the map like the hazard
    /// bubbles, so they do not block touches on the map under them.
    private func distanceLabels(_ lines: [StrokeLine], proxy: MapProxy) -> some View {
        // Reading the counter redraws the labels as the camera moves
        _ = camera.changes
        return ZStack {
            ForEach(lines.indices, id: \.self) { index in
                if let point = proxy.convert(lines[index].midpoint, to: .local) {
                    DistanceLabel(value: lines[index].yards, unit: .yards, identifier: "StrokeDistance_\(index + 1)")
                        .fixedSize()
                        .position(point)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
    }

    /// Thin lines from the player to the target, and from the target to the green center. They
    /// stop short of the bullseye, so it stays clear. None without a target.
    private var targetLines: [[CLLocationCoordinate2D]] {
        guard let target else { return [] }
        let gap = Double(TargetMarker.lineGap) * camera.metersPerPoint
        var lines: [[CLLocationCoordinate2D]] = []
        if let location = services.locationManager.lastLocation,
           let end = MapGeometry.lineEnd(at: target, toward: location.coordinate, gap: gap) {
            lines.append([location.coordinate, end])
        }
        if let greenCenter = round.greenCenter(holeIndex: shownHoleIndex),
           let start = MapGeometry.lineEnd(at: target, toward: greenCenter, gap: gap) {
            lines.append([start, greenCenter])
        }
        return lines
    }
}
