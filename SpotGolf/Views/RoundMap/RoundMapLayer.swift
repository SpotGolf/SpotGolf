import MapKit
import SwiftUI

/// The map of the shown hole: the player, the pin, the spots, the GPS track, the tapped target
/// and its lines, hazard distances, and stroke suggestions while editing. A long press adds a
/// spot while editing, and a spot can be lifted and dragged to move it.
struct RoundMapLayer: View {
    let round: Round
    let shownHoleIndex: Int
    let isEditing: Bool
    /// The hole's track as the map draws it, and all of its fixes.
    let trackLine: [CLLocationCoordinate2D]
    let holeTrack: [TrackPoint]
    let suggestions: [StrokeSuggestion]
    @Binding var camera: MapCameraState
    @Binding var target: CLLocationCoordinate2D?
    @Binding var spot: SpotSelection

    @Environment(PhoneServices.self) private var services
    @State private var draggingStroke: Stroke?
    @State private var dragOffset: CGSize = .zero

    private static let dragLiftOffset: CGFloat = -30

    var body: some View {
        let strokesToShow = round.hole(at: shownHoleIndex).strokes
        MapReader { proxy in
            let targetLines = targetLines
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
                    Annotation("", coordinate: stroke.coordinate) {
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
                                    services.roundStore.addSuggestedStroke(suggestion, holeIndex: shownHoleIndex,
                                                                           roundID: round.id, holeTrack: holeTrack)
                                }
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapCompass()
            }
            .overlay {
                hazardBubbles(proxy: proxy)
            }
            .onMapCameraChange(frequency: .continuous) { context in
                camera.changes &+= 1
                let metersAcross = context.rect.size.width / MKMapPointsPerMeterAtLatitude(context.region.center.latitude)
                if let metersPerPoint = MapGeometry.metersPerPoint(mapSize: camera.mapSize, heading: context.camera.heading,
                                                                   metersAcross: metersAcross) {
                    camera.metersPerPoint = metersPerPoint
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { camera.mapSize = $0 }
            .onMapCameraChange(frequency: .onEnd) { context in
                guard camera.followsUserLocation, let userLocation = services.locationManager.lastLocation else { return }
                let mapCenter = CLLocation(latitude: context.region.center.latitude,
                                           longitude: context.region.center.longitude)
                if mapCenter.distance(from: userLocation) > 30 {
                    camera.followsUserLocation = false
                }
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
                            let stroke = Stroke(coordinate: coordinate)
                            spot.newIndex = round.hole(at: shownHoleIndex).strokes.count // capture before append
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

    private func strokeColor(for type: StrokeType) -> Color {
        switch type {
        case .regular: return .blue
        case .penalty: return .red
        case .outOfBounds: return .white
        }
    }

    private func spotMarker(index: Int, stroke: Stroke, proxy: MapProxy) -> some View {
        let isDragging = draggingStroke?.id == stroke.id
        let pinColor = strokeColor(for: stroke.type)
        let textColor: Color = stroke.type == .outOfBounds ? .black : .white
        return VStack(spacing: 0) {
            Button {
                guard isEditing else { return }
                if let holeIdx = round.holeIndex(containing: stroke.id),
                   let strokeIdx = round.holes[holeIdx].strokes.firstIndex(where: { $0.id == stroke.id }) {
                    spot.newIndex = strokeIdx
                }
                spot.stroke = stroke
            } label: {
                Circle()
                    .fill(isDragging ? Color.orange : pinColor)
                    .frame(width: isDragging ? 42 : 28, height: isDragging ? 42 : 28)
                    .overlay {
                        Text("\(index + 1)")
                            .font(isDragging ? .body : .caption)
                            .fontWeight(.bold)
                            .foregroundStyle(isDragging ? .white : textColor)
                    }
                    .overlay {
                        if !isDragging && stroke.type == .outOfBounds {
                            Circle().stroke(Color.gray, lineWidth: 1.5)
                        }
                    }
                    .shadow(color: isDragging ? .orange.opacity(0.4) : .black.opacity(0.2),
                            radius: isDragging ? 8 : 2, y: isDragging ? 2 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Stroke_\(index + 1)")

            // Callout line from lifted marker down to map position
            if isDragging {
                Rectangle()
                    .fill(Color.orange.opacity(0.6))
                    .frame(width: 2, height: -Self.dragLiftOffset)
            }
        }
        .offset(y: isDragging ? Self.dragLiftOffset : 0)
        .offset(isDragging ? dragOffset : .zero)
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
