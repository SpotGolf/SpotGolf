import MapKit
import SwiftUI

/// The map of the shown hole: the player, the pin, the spots, the GPS track, the tapped target
/// and its lines, hazard distances, stroke suggestions, the lines between the hole's strokes
/// with the yards along each when they are turned on, and the Caddie's club and aim with its shot
/// pattern when that is turned on. Tapping a spot opens it, a long press adds a spot, and a long
/// press on a spot holds it. A held spot, new or not, can be dragged into place before the finger
/// lifts.
struct RoundMapLayer: View {
    let round: Round
    let shownHoleIndex: Int
    let showsStrokeLines: Bool
    /// The Caddie's club and aim, while the dot menu's Caddie item is on and there is one.
    let caddieShot: CaddieShot?
    /// The water and sand shapes the Caddie's shot could reach, marked where the pattern covers
    /// them.
    let caddieHazards: [[CLLocationCoordinate2D]]
    /// A drag on the shot pattern moves the aim to this point on the ground.
    let moveCaddieAim: (CLLocationCoordinate2D) -> Void
    /// Set while a spot is held, so the map holds its hole.
    @Binding var isDraggingSpot: Bool
    /// The hole's track as the map draws it, and all of its fixes.
    let trackLine: [CLLocationCoordinate2D]
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
    /// Where the aim point was when a drag on the shot pattern started, until the finger lifts.
    @State private var caddieDragAim: CGPoint?

    var body: some View {
        let strokesToShow = round.hole(at: shownHoleIndex).strokes
        MapReader { proxy in
            let targetLines = targetLines
            let strokeLines = showsStrokeLines ? MapGeometry.strokeLines(strokesToShow) : []
            // The map holds still while a spot is held or the pattern is dragged, or it would pan
            // under the finger
            Map(position: $camera.position, interactionModes: isHoldingSpot || caddieDragAim != nil ? [] : .all) {
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
                        Annotation("", coordinate: coordinate, anchor: SuggestionPin.anchor) {
                            SuggestionPin(kind: suggestion.kind) {
                                SpotActions.takeSuggestion(suggestion, round: round, holeIndex: shownHoleIndex,
                                                           services: services, spot: &spot)
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
                caddiePattern(proxy: proxy)
            }
            .overlay {
                hazardBubbles(proxy: proxy)
            }
            .overlay {
                caddieAimMarker(proxy: proxy)
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
            .gesture(
                CaddieDragGesture(space: .local, isOnPattern: { isOnCaddiePattern($0, proxy: proxy) }) { start, finger in
                    guard let caddieShot,
                          let aim = caddieDragAim ?? proxy.convert(caddieShot.aimCoordinate, to: .local) else { return }
                    caddieDragAim = aim
                    // The aim keeps its place under the finger
                    let moved = CGPoint(x: aim.x + finger.x - start.x, y: aim.y + finger.y - start.y)
                    if let coordinate = proxy.convert(moved, from: .local) {
                        moveCaddieAim(coordinate)
                    }
                } ended: {
                    caddieDragAim = nil
                }
            )
        }
    }

    /// True for a point on the Caddie's shot pattern: inside its largest region, between the
    /// player and that region, or on the aim point's marker.
    private func isOnCaddiePattern(_ point: CGPoint, proxy: MapProxy) -> Bool {
        guard let caddieShot,
              let start = proxy.convert(caddieShot.startCoordinate, to: .local),
              let aim = proxy.convert(caddieShot.aimCoordinate, to: .local) else { return false }
        // The marker's ring, and its label to the right of it
        let marker = CGRect(x: aim.x - 22, y: aim.y - 22, width: 110, height: 44)
        if marker.contains(point) { return true }
        guard let outer = caddieShot.shape?.outer else { return false }
        let ring = caddieShot.outline(outer).compactMap { proxy.convert($0, to: .local) }
        guard ring.count == outer.ring.count, ring.count >= 3 else { return false }
        if Self.closedPath(ring).contains(point) { return true }
        // From the player to the region's leftmost and rightmost points
        guard let left = outer.ring.indices.min(by: { outer.ring[$0].x < outer.ring[$1].x }),
              let right = outer.ring.indices.max(by: { outer.ring[$0].x < outer.ring[$1].x }) else { return false }
        return Self.closedPath([start, ring[left], ring[right]]).contains(point)
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
    /// swallows touches and would block a long press that adds a stroke underneath it. That puts
    /// them over the map's pins, so the shape of every pin is cut out of them and the pin under
    /// a bubble shows through, as if it stood on top.
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
            if !hazards.isEmpty {
                pinCutouts(proxy: proxy)
                    .blendMode(.destinationOut)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keeps the cut to the bubbles: without it the pins' shapes would be cut out of the map
        .compositingGroup()
        .clipped()
        .allowsHitTesting(false)
    }

    /// The map's suggestion pins, spot pins and flag, each drawn again where the map has it. Only
    /// their shapes are used, to cut them out of the hazard bubbles. They are drawn on a canvas,
    /// so they are not a second set of pins to VoiceOver or to a touch.
    private func pinCutouts(proxy: MapProxy) -> some View {
        let strokes = round.hole(at: shownHoleIndex).strokes
        let pin = round.pin(onHole: shownHoleIndex)
        // Room under a pin for its dot, and around the flag for its larger sizes: a canvas cuts
        // a symbol off at its edges
        let pinRoom: CGFloat = 8
        let flagRoom: CGFloat = 24
        return Canvas { context, _ in
            for suggestion in suggestions {
                if let point = suggestion.coordinate.flatMap({ proxy.convert($0, to: .local) }),
                   let symbol = context.resolveSymbol(id: suggestion.id) {
                    context.draw(symbol, at: CGPoint(x: point.x, y: point.y + pinRoom + SuggestionPin.tapPadding),
                                 anchor: .bottom)
                }
            }
            for stroke in strokes {
                if let point = proxy.convert(stroke.coordinate, to: .local), let symbol = context.resolveSymbol(id: stroke.id) {
                    let offset = draggingStroke?.id == stroke.id ? dragOffset(of: stroke, proxy: proxy) : .zero
                    context.draw(symbol, at: CGPoint(x: point.x + offset.width, y: point.y + offset.height + pinRoom),
                                 anchor: .bottom)
                }
            }
            if let pin, let point = proxy.convert(pin.coordinate, to: .local), let symbol = context.resolveSymbol(id: "flag") {
                // The base of the pole on the pin, as the map has it
                context.draw(symbol, at: CGPoint(x: point.x - PinFlag.poleWidth / 2 - flagRoom, y: point.y + flagRoom),
                             anchor: .bottomLeading)
            }
        } symbols: {
            ForEach(suggestions) { suggestion in
                SuggestionPin(kind: suggestion.kind) {}
                    .fixedSize()
                    .padding(.bottom, pinRoom)
                    .tag(suggestion.id)
            }
            ForEach(Array(strokes.enumerated()), id: \.element.id) { index, stroke in
                SpotPin(number: index + 1, stroke: stroke, isDragging: draggingStroke?.id == stroke.id) {}
                    .fixedSize()
                    .padding(.bottom, pinRoom)
                    .tag(stroke.id)
            }
            if let pin {
                PinFlag(source: pin.source, scale: MapGeometry.flagScale(metersPerPoint: camera.metersPerPoint),
                        raised: MapGeometry.hasPinsOnGreen(round, holeIndex: shownHoleIndex, suggestions: suggestions))
                    .fixedSize()
                    .padding(flagRoom)
                    .tag("flag")
            }
        }
        .accessibilityHidden(true)
    }

    /// The Caddie's aim point, and the yards from it to the pin on the middle of the line between
    /// them. Drawn over the map like the hazard bubbles so they do not block touches on the map
    /// under them.
    @ViewBuilder
    private func caddieAimMarker(proxy: MapProxy) -> some View {
        // Reading the counter redraws the marker as the camera moves
        let _ = camera.changes
        ZStack {
            if let caddieShot, let point = proxy.convert(caddieShot.aimCoordinate, to: .local) {
                CaddieAimMarker(club: caddieShot.club, yards: caddieShot.yards)
                    .fixedSize()
                    .position(point)
                // On the middle of the line from the aim point to the pin, as Distances has them
                if let pin = caddiePin(for: caddieShot), let pinPoint = proxy.convert(pin, to: .local),
                   let toPin = yardsToPin(from: caddieShot.aimCoordinate) {
                    DistanceLabel(value: toPin, unit: .yards, identifier: "CaddieToPin", background: .yellow)
                        .fixedSize()
                        .position(x: (point.x + pinPoint.x) / 2, y: (point.y + pinPoint.y) / 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
    }

    /// Where the Caddie's line on from the aim point goes: the shown hole's pin, or its green's
    /// center without one. Nil when the aim point is on the green already.
    private func caddiePin(for shot: CaddieShot) -> CLLocationCoordinate2D? {
        guard !round.isOnGreen(shot.aimCoordinate, holeIndex: shownHoleIndex) else { return nil }
        return round.targetCoordinate(holeIndex: shownHoleIndex)
    }

    /// Yards from `coordinate` to the shown hole's pin, or its green's center without one.
    private func yardsToPin(from coordinate: CLLocationCoordinate2D) -> Int? {
        HoleOverview.yardsToPin(round, holeIndex: shownHoleIndex,
                                from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    /// The Caddie's shot pattern: the regions that hold 95%, 80% and 50% of the club's shots,
    /// each with a solid outline; stripes over the water and sand the largest region covers; a
    /// thick line from the player's dot to short of the aim point's ring; and a dotted line on
    /// from the ring to the pin unless the aim point is on the green. Drawn over the map like
    /// the hazard bubbles, because the map draws shapes it is handed after the advice is worked
    /// out in the background only when something else makes it redraw, such as a touch or a
    /// camera move. The fills are see-through, so spots and the flag show through. See
    /// plans/2026-11-11-shot-dispersion.md, section 6.
    @ViewBuilder
    private func caddiePattern(proxy: MapProxy) -> some View {
        // Reading the counter redraws the pattern as the camera moves
        let _ = camera.changes
        if let caddieShot {
            // Largest first, so each smaller region is drawn over it
            let regions = (caddieShot.shape?.regions ?? []).reversed().map { region in
                Self.closedPath(caddieShot.outline(region).compactMap { proxy.convert($0, to: .local) })
            }
            let hazards = caddieHazards.map { hazard in
                Self.closedPath(hazard.compactMap { proxy.convert($0, to: .local) })
            }
            let start = proxy.convert(caddieShot.startCoordinate, to: .local)
            let aim = proxy.convert(caddieShot.aimCoordinate, to: .local)
            let pin = caddiePin(for: caddieShot).flatMap { proxy.convert($0, to: .local) }
            Canvas { context, _ in
                for (index, region) in regions.enumerated() {
                    let look = CaddiePatternLook.regions[min(index, CaddiePatternLook.regions.count - 1)]
                    context.fill(region, with: .color(look.fill))
                    context.stroke(region, with: .color(look.line), lineWidth: look.lineWidth)
                }
                if let outer = regions.first {
                    Self.drawHazards(hazards, inside: outer, in: &context)
                }
                guard let aim else { return }
                // Lines from the player start past their dot
                let dotRadius: CGFloat = 12
                let ringGap = CaddieAimMarker.ring / 2 + 4
                if let start, let line = Self.line(from: start, to: aim, startGap: dotRadius, endGap: ringGap) {
                    let path = Path { $0.addLines(line) }
                    context.stroke(path, with: .color(.yellow), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    context.stroke(path, with: .color(CaddiePatternLook.aimDash),
                                   style: StrokeStyle(lineWidth: 1, lineCap: .butt, dash: [5, 4]))
                }
                // On from the aim point to the pin, with its yards on it
                if let pin, let line = Self.line(from: aim, to: pin, startGap: ringGap, endGap: 0) {
                    // Round dots: a dash of almost nothing with round caps
                    context.stroke(Path { $0.addLines(line) }, with: .color(.yellow),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The part of each water and sand shape inside the pattern's largest region: striped, with a
    /// solid outline.
    private static func drawHazards(_ hazards: [Path], inside outer: Path, in context: inout GraphicsContext) {
        let bounds = outer.boundingRect
        for hazard in hazards where hazard.boundingRect.intersects(bounds) {
            let covered = hazard.intersection(outer)
            guard !covered.isEmpty else { continue }
            let box = covered.boundingRect
            let stripes = Path { path in
                // Up and to the right, 6 points apart
                for x in stride(from: box.minX - box.height, through: box.maxX, by: 6) {
                    path.move(to: CGPoint(x: x, y: box.maxY))
                    path.addLine(to: CGPoint(x: x + box.height, y: box.minY))
                }
            }
            context.fill(covered, with: .color(CaddiePatternLook.hazard.opacity(0.15)))
            var clipped = context
            clipped.clip(to: covered)
            clipped.stroke(stripes, with: .color(CaddiePatternLook.hazard), lineWidth: 1.5)
            context.stroke(covered, with: .color(CaddiePatternLook.hazard), lineWidth: 2)
        }
    }

    private static func closedPath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard points.count >= 3 else { return }
            path.addLines(points)
            path.closeSubpath()
        }
    }

    /// The line from `start` to `end`, cut `startGap` and `endGap` points short at each end. Nil
    /// when that leaves nothing.
    private static func line(from start: CGPoint, to end: CGPoint, startGap: CGFloat, endGap: CGFloat) -> [CGPoint]? {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > startGap + endGap else { return nil }
        let (dx, dy) = ((end.x - start.x) / length, (end.y - start.y) / length)
        return [CGPoint(x: start.x + dx * startGap, y: start.y + dy * startGap),
                CGPoint(x: end.x - dx * endGap, y: end.y - dy * endGap)]
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

/// The colors and line widths of the Caddie's shot pattern. See
/// plans/2026-11-11-shot-dispersion.md, section 6.
private enum CaddiePatternLook {
    struct Region {
        let fill: Color
        let line: Color
        let lineWidth: CGFloat
    }

    private static let darkGreen = Color(red: 0.10, green: 0.36, blue: 0.14)
    private static let navy = Color(red: 0.07, green: 0.10, blue: 0.30)

    /// The regions that hold 95%, 80% and 50% of shots.
    static let regions = [
        Region(fill: .white.opacity(0.30), line: Color(white: 0.4), lineWidth: 1),
        Region(fill: darkGreen.opacity(0.20), line: navy, lineWidth: 1.5),
        Region(fill: darkGreen.opacity(0.45), line: navy, lineWidth: 2),
    ]
    /// Water and sand inside the pattern.
    static let hazard = Color(red: 0.92, green: 0.33, blue: 0.10)
    /// The dashes along the middle of the aim line.
    static let aimDash = Color(white: 0.35)
}
