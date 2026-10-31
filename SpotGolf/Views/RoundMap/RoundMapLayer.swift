import MapKit
import SwiftUI

/// The map of the shown hole: the player, the pin, the spots, the GPS track, the tapped target
/// and its lines, hazard distances, stroke suggestions, and the lines between the hole's strokes
/// with the yards along each when they are turned on. Tapping a spot opens it, a long press adds
/// a spot, and a long press on a spot holds it. A held spot, new or not, can be dragged into
/// place before the finger lifts.
struct RoundMapLayer: View {
    let round: Round
    let shownHoleIndex: Int
    let showsStrokeLines: Bool
    /// Set while a spot is held, so the map holds its hole.
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
    /// The spot a long press holds, and where it is dragged, until the finger lifts.
    @State private var draggingStroke: Stroke?
    @State private var strokeDrag: SpotDrag?
    /// The spot a long press is adding, until the finger lifts.
    @State private var newSpot: SpotDrag?
    /// A dragged spot lands this far above the finger, where a thumb does not hide it.
    private static let dropLift: CGFloat = 70

    var body: some View {
        let strokesToShow = round.hole(at: shownHoleIndex).strokes
        MapReader { proxy in
            let targetLines = targetLines
            let strokeLines = showsStrokeLines ? MapGeometry.strokeLines(strokesToShow) : []
            // The map holds still while a spot is held, or it would pan under the finger
            Map(position: $camera.position, interactionModes: isHoldingSpot ? [] : .all) {
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
            .overlay {
                newSpotMarker(number: strokesToShow.count + 1, proxy: proxy)
                    .allowsHitTesting(false)
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
            .onChange(of: isHoldingSpot) { _, holding in
                isDraggingSpot = holding
            }
            .gesture(
                SpotPressGesture(minimumDuration: 0.5, space: .local, lift: Self.dropLift) { newSpot = $0 } ended: { drag in
                    if let drag, let coordinate = proxy.convert(drag.dot, from: .local) {
                        SpotActions.addSpot(at: coordinate, round: round, holeIndex: shownHoleIndex,
                                            startWindow: startWindow, services: services, spot: &spot)
                    }
                    newSpot = nil
                }
            )
        }
    }

    private var isHoldingSpot: Bool {
        draggingStroke != nil || newSpot != nil
    }

    /// The spot a long press is adding, drawn over the map like the hazard bubbles until the
    /// finger lifts.
    @ViewBuilder
    private func newSpotMarker(number: Int, proxy: MapProxy) -> some View {
        if let newSpot, let coordinate = proxy.convert(newSpot.dot, from: .local) {
            SpotPin(number: number, stroke: Stroke(coordinate: coordinate), isDragging: true) {}
                .standing(at: newSpot.dot)
                .allowsHitTesting(false)
        }
    }

    private func spotMarker(index: Int, stroke: Stroke, proxy: MapProxy) -> some View {
        let isDragging = draggingStroke?.id == stroke.id
        return SpotPin(number: index + 1, stroke: stroke, isDragging: isDragging) {
            if let holeIdx = round.holeIndex(containing: stroke.id),
               let strokeIdx = round.holes[holeIdx].strokes.firstIndex(where: { $0.id == stroke.id }) {
                spot.newIndex = strokeIdx
            }
            spot.stroke = stroke
        }
        .offset(isDragging ? dragOffset(of: stroke, proxy: proxy) : .zero)
        .gesture(
            SpotPressGesture(minimumDuration: 0.3, space: .global, lift: Self.dropLift,
                             dot: { proxy.convert(stroke.coordinate, to: .global) }) { drag in
                draggingStroke = stroke
                strokeDrag = drag
            } ended: { drag in
                // A spot the finger did not move stays where it is
                if let drag, drag.follows, let coordinate = proxy.convert(drag.dot, from: .global) {
                    SpotActions.move(stroke, to: coordinate, round: round, startWindow: startWindow,
                                     services: services)
                }
                draggingStroke = nil
                strokeDrag = nil
            }
        )
    }

    /// How far the held spot is shown from where it stands.
    private func dragOffset(of stroke: Stroke, proxy: MapProxy) -> CGSize {
        guard let strokeDrag, let dot = proxy.convert(stroke.coordinate, to: .global) else { return .zero }
        return CGSize(width: strokeDrag.dot.x - dot.x, height: strokeDrag.dot.y - dot.y)
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
