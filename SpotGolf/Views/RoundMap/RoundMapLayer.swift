import MapKit
import SwiftUI

/// The map of the shown hole: the player, the pin, the spots, the GPS track, the tapped target
/// and its lines, hazard distances, and stroke suggestions while editing. Tapping a spot shows
/// or hides the lines between the hole's strokes, with the yards along each. A long press adds
/// a spot while editing, and a spot can be lifted and dragged to move it.
struct RoundMapLayer: View {
    let round: Round
    let shownHoleIndex: Int
    let isEditing: Bool
    /// The hole's track as the map draws it, and all of its fixes.
    let trackLine: [CLLocationCoordinate2D]
    let holeTrack: [TrackPoint]
    let suggestions: [StrokeSuggestion]
    let mapStyle: MapStyleChoice
    @Binding var camera: MapCameraState
    @Binding var target: CLLocationCoordinate2D?
    @Binding var spot: SpotSelection

    @Environment(PhoneServices.self) private var services
    @State private var draggingStroke: Stroke?
    @State private var dragOffset: CGSize = .zero
    /// The lines between the strokes are shown. Tapping a spot outside editing turns them on and off.
    @State private var showsStrokeLines = false

    var body: some View {
        let strokesToShow = round.hole(at: shownHoleIndex).strokes
        MapReader { proxy in
            let targetLines = targetLines
            let strokeLines = showsStrokeLines ? MapGeometry.strokeLines(strokesToShow) : []
            Map(position: $camera.position) {
                if round.isActive {
                    UserAnnotation()
                }
                if let pin = round.pin(onHole: shownHoleIndex) {
                    // The base of the pole sits on the pin
                    Annotation("", coordinate: pin.coordinate, anchor: PinFlag.base) {
                        PinFlag(source: pin.source, scale: MapGeometry.flagScale(metersPerPoint: camera.metersPerPoint))
                    }
                }
                ForEach(Array(strokesToShow.enumerated()), id: \.element.id) { index, stroke in
                    // The dot under the pin sits on the stroke
                    Annotation("", coordinate: stroke.coordinate, anchor: .bottom) {
                        spotMarker(index: index, stroke: stroke, proxy: proxy)
                    }
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
                if isEditing {
                    ForEach(suggestions) { suggestion in
                        if let coordinate = suggestion.coordinate {
                            Annotation("", coordinate: coordinate, anchor: .bottom) {
                                SuggestionPin(isContact: suggestion.isContact) {
                                    guard let stroke = services.roundStore.addSuggestedStroke(
                                        suggestion, holeIndex: shownHoleIndex, roundID: round.id, holeTrack: holeTrack,
                                        bag: services.golfBag.bag) else { return }
                                    spot.newIndex = round.hole(at: shownHoleIndex).strokes.firstIndex { $0.id == stroke.id } ?? 0
                                    spot.stroke = stroke
                                }
                            }
                        }
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
                // Distances come from the player's location, and taps while editing are for spots
                guard round.isActive, !isEditing,
                      let coordinate = proxy.convert(point, from: .local) else { return }
                target = coordinate
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag):
                            guard isEditing, let drag,
                                  let coordinate = proxy.convert(drag.location, from: .global) else { return }
                            spot.newIndex = round.hole(at: shownHoleIndex).strokes.count // capture before append
                            let stroke = Stroke(coordinate: coordinate,
                                                club: HoleOverview.guessedClub(round, holeIndex: shownHoleIndex, strokeIndex: spot.newIndex,
                                                                               at: coordinate, bag: services.golfBag.bag))
                            // Hit when the player was nearest to it, going by the hole's GPS
                            services.roundStore.addStroke(to: round.id, holeIndex: shownHoleIndex, stroke: stroke,
                                                          hitAt: StrokeFinder.estimatedTime(of: stroke, in: holeTrack))
                            spot.stroke = stroke
                        default:
                            break
                        }
                    }
            )
        }
    }

    private func spotMarker(index: Int, stroke: Stroke, proxy: MapProxy) -> some View {
        SpotPin(number: index + 1, stroke: stroke, isDragging: draggingStroke?.id == stroke.id) {
            guard isEditing else {
                showsStrokeLines.toggle()
                return
            }
            if let holeIdx = round.holeIndex(containing: stroke.id),
               let strokeIdx = round.holes[holeIdx].strokes.firstIndex(where: { $0.id == stroke.id }) {
                spot.newIndex = strokeIdx
            }
            spot.stroke = stroke
        }
        .offset(draggingStroke?.id == stroke.id ? dragOffset : .zero)
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(coordinateSpace: .global))
                .onChanged { value in
                    guard isEditing else { return }
                    switch value {
                    case .second(true, let drag):
                        if draggingStroke == nil {
                            withAnimation(.easeOut(duration: 0.15)) {
                                draggingStroke = stroke
                            }
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                        }
                        if let drag {
                            dragOffset = drag.translation
                        }
                    default:
                        break
                    }
                }
                .onEnded { value in
                    guard isEditing else { return }
                    switch value {
                    case .second(true, let drag):
                        if let drag,
                           let coordinate = proxy.convert(drag.location, from: .global) {
                            services.roundStore.moveStroke(stroke, to: coordinate, in: round.id)
                        }
                    default:
                        break
                    }
                    draggingStroke = nil
                    dragOffset = .zero
                }
        )
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
                    DistanceLabel(yards: lines[index].yards, number: index + 1)
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
