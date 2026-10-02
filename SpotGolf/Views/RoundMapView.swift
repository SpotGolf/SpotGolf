import SwiftUI
import MapKit
import CourseDataSwift

struct RoundMapView: View {
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)

    let roundID: UUID
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var suggestionStore: SuggestionStore
    @EnvironmentObject var streamStore: StreamStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private var round: Round? {
        roundStore.rounds.first(where: { $0.id == roundID })
    }

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var followsUserLocation = true
    @State private var selectedStroke: Stroke?
    @State private var showDeleteConfirm = false
    @State private var draggingStroke: Stroke?
    @State private var dragOffset: CGSize = .zero
    @State private var newSpotIndex: Int = 0
    @State private var holeAdvancer = HoleAdvancer()
    /// A hole the user picked to look at. Nil while the view follows the round's current hole.
    @State private var viewingHoleIndex: Int?
    @State private var hasInitialPan = false
    @State private var pendingPanToHole = false
    @State private var isEditing = false
    /// The whole round's GPS, and the part of it on the hole shown.
    @State private var roundTrack: [TrackPoint] = []
    @State private var holeTrack: [TrackPoint] = []
    @State private var suggestions: [StrokeSuggestion] = []
    @State private var cameraChanges = 0
    @State private var showHoleTimes = false

    var body: some View {
        Group {
            if let round {
                roundContent(round)
            }
        }
        .onAppear {
            locationManager.startUpdating()
            reloadTrack()
            // A past round shows its holes, not the player, so it does not wait for a location
            if let round, !round.isActive, !hasInitialPan {
                hasInitialPan = true
                panToHole()
            }
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .onReceive(locationManager.$lastLocation) { location in
            if !hasInitialPan, location != nil, round != nil {
                hasInitialPan = true
                panToHole()
            } else if followsUserLocation, round?.isActive == true, let location {
                if let heading = shownHoleHeading() {
                    position = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 600, heading: heading, pitch: 0))
                } else {
                    position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
                }
            }
            if let round, round.isActive, !holeAdvancer.isPaused, let location {
                if let detected = holeAdvancer.advance(location: location, courseSelection: round.courseSelection, currentHoleIndex: round.currentHoleIndex) {
                    roundStore.startHole(detected, roundID: round.id, source: .autoAdvance)
                    pendingPanToHole = true
                }
            }
        }
        .onChange(of: roundStore.rounds) {
            if round == nil {
                dismiss()
            }
            if pendingPanToHole {
                pendingPanToHole = false
                panToHole()
            }
            refreshSuggestions()
        }
        .onChange(of: round.map(shownHoleIndex)) {
            // Also covers a hole chosen on the watch
            isEditing = false
            panToHole()
            reloadTrack()
        }
        .onReceive(suggestionStore.$hidden) { _ in
            refreshSuggestions()
        }
        .onChange(of: streamStore.revision) {
            // Records arrived from the watch
            reloadTrack()
        }
    }

    /// The hole the map, header, and distances describe. A past round opens on its first hole.
    private func shownHoleIndex(_ round: Round) -> Int {
        viewingHoleIndex ?? (round.isActive ? round.currentHoleIndex : 0)
    }

    @ViewBuilder
    private func roundContent(_ round: Round) -> some View {
        VStack(spacing: 0) {
            holeHeader(round)
            RoundSyncBanner(round: round)
            ZStack(alignment: .top) {
                mapView(round)
                overlayView(round)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showHoleTimes) {
            HoleTimelineView(roundID: round.id)
        }
        // The header has its own back button, so the bar is hidden
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { selectedStroke != nil && !showDeleteConfirm },
            set: { if !$0 && !showDeleteConfirm { selectedStroke = nil } }
        )) {
            spotEditSheet(round)
        }
        .alert("Delete Spot", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let stroke = selectedStroke {
                    roundStore.removeStroke(stroke, from: round.id)
                }
                selectedStroke = nil
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirm = false
            }
        } message: {
            Text("Are you sure you want to delete this spot?")
        }
    }

    private func mapView(_ round: Round) -> some View {
        let strokesToShow = round.hole(at: shownHoleIndex(round)).strokes
        return MapReader { proxy in
            Map(position: $position) {
                if round.isActive {
                    UserAnnotation()
                }
                ForEach(Array(strokesToShow.enumerated()), id: \.element.id) { index, stroke in
                    Annotation("", coordinate: stroke.coordinate) {
                        spotMarker(index: index, stroke: stroke, round: round, proxy: proxy)
                    }
                }
                if holeTrack.count >= 2 {
                    MapPolyline(coordinates: holeTrack.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(Color.blue.opacity(0.7),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7]))
                }
                if isEditing {
                    ForEach(suggestions) { suggestion in
                        if let coordinate = suggestion.coordinate {
                            Annotation("", coordinate: coordinate, anchor: .bottom) {
                                suggestionPin(suggestion, round: round)
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapCompass()
            }
            .overlay {
                hazardBubbles(round, proxy: proxy)
            }
            .onMapCameraChange(frequency: .continuous) { _ in
                cameraChanges &+= 1
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                guard followsUserLocation, let userLocation = locationManager.lastLocation else { return }
                let mapCenter = CLLocation(latitude: context.region.center.latitude,
                                           longitude: context.region.center.longitude)
                if mapCenter.distance(from: userLocation) > 30 {
                    followsUserLocation = false
                }
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
                            let holeIndex = shownHoleIndex(round)
                            newSpotIndex = round.hole(at: holeIndex).strokes.count // capture before append
                            roundStore.addStroke(to: round.id, holeIndex: holeIndex, stroke: stroke)
                            selectedStroke = stroke
                        default:
                            break
                        }
                    }
            )
        }
    }

    private static let dragLiftOffset: CGFloat = -30

    private func strokeColor(for type: StrokeType) -> Color {
        switch type {
        case .regular: return .blue
        case .penalty: return .red
        case .outOfBounds: return .white
        }
    }

    private func spotMarker(index: Int, stroke: Stroke, round: Round, proxy: MapProxy) -> some View {
        let isDragging = draggingStroke?.id == stroke.id
        let pinColor = strokeColor(for: stroke.type)
        let textColor: Color = stroke.type == .outOfBounds ? .black : .white
        return VStack(spacing: 0) {
            Button {
                guard isEditing else { return }
                if let holeIdx = round.holeIndex(containing: stroke.id) {
                    let hole = round.holes[holeIdx]
                    if let strokeIdx = hole.strokes.firstIndex(where: { $0.id == stroke.id }) {
                        newSpotIndex = strokeIdx
                    }
                }
                selectedStroke = stroke
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
                            roundStore.moveStroke(stroke, to: coordinate, in: round.id)
                        }
                    default:
                        break
                    }
                    draggingStroke = nil
                    dragOffset = .zero
                }
        )
    }

    private func overlayView(_ round: Round) -> some View {
        VStack {
            // Distances come from the player's location, so a past round has none
            if round.isActive {
                HStack {
                    Spacer()
                    keyInformation(round)
                }
            }
            Spacer()
            buttonBar(round)
        }
    }

    // MARK: - Header

    /// Every hole as a circle, with a back button and the score box on top at each end.
    /// The current hole's par and distance sit underneath.
    private func holeHeader(_ round: Round) -> some View {
        let holeCount = round.courseSelection.orderedHoles.count
        return VStack(spacing: 6) {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<holeCount, id: \.self) { index in
                                holeCircle(index, round)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    // The first and last holes can scroll to the center of the display
                    .contentMargins(.horizontal, max(0, geometry.size.width / 2 - 18), for: .scrollContent)
                    .mask(holeFadeMask)
                    .onAppear {
                        proxy.scrollTo(shownHoleIndex(round), anchor: .center)
                    }
                    .onChange(of: shownHoleIndex(round)) {
                        withAnimation {
                            proxy.scrollTo(shownHoleIndex(round), anchor: .center)
                        }
                    }
                }
            }
            .frame(height: 40)
            .overlay(alignment: .leading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(width: 44, height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.bar))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .accessibilityLabel("Back")
            }
            .overlay(alignment: .trailing) {
                scoreBox(round)
                    .padding(.trailing, 12)
            }

            if let summary = holeSummary(round) {
                Text(summary)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("HoleSummary")
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// Hides the holes behind the back button and the score box, with a small gap,
    /// and fades them out as they come near either one.
    private var holeFadeMask: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 64)  // back button (12 + 44) and a gap
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 32)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 32)
            Color.clear.frame(width: 72)  // score box (52 + 12) and a gap
        }
    }

    /// The round's total strokes, and how they compare to par on the finished holes.
    private func scoreBox(_ round: Round) -> some View {
        let total = round.allStrokes.count
        // Every played hole of a past round is finished
        let finished = round.holes.indices.filter {
            (!round.isActive || $0 != round.currentHoleIndex) && !round.holes[$0].strokes.isEmpty
        }
        let pars = finished.compactMap { round.courseHole(at: $0)?.par }
        let toPar: String? = pars.count == finished.count && !finished.isEmpty
            ? Self.toParText(finished.reduce(0) { $0 + round.holes[$1].strokeCount } - pars.reduce(0, +))
            : nil
        return VStack(spacing: 0) {
            Text("\(total)")
                .font(.headline)
                .monospacedDigit()
            if let toPar {
                Text(toPar)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 52, height: 40)
        .background(RoundedRectangle(cornerRadius: 8).fill(.bar))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Score")
        .accessibilityValue(toPar.map { "\(total), \($0)" } ?? "\(total)")
        .accessibilityIdentifier("ScoreBox")
    }

    /// "E", "+2", or "-1".
    private static func toParText(_ diff: Int) -> String {
        diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)"
    }

    private func holeCircle(_ index: Int, _ round: Round) -> some View {
        let isShown = index == shownHoleIndex(round)
        // While another hole is shown, the round's current hole keeps a green ring
        let isCurrent = round.isActive && index == round.currentHoleIndex
        let isPlayed = index < round.holes.count && !round.holes[index].strokes.isEmpty
        return Button {
            selectHole(index, round)
        } label: {
            Text("\(index + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isShown ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isShown ? Color.green : isPlayed ? Color.green.opacity(0.18) : Color.clear))
                .overlay(Circle().stroke(isShown || isCurrent ? Color.green : Color.secondary.opacity(0.5),
                                         lineWidth: isCurrent && !isShown ? 3 : 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hole \(index + 1)")
        .accessibilityValue(isCurrent ? "Current hole" : "")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }

    /// Shows a hole without changing the round's current hole, and pauses automatic
    /// hole changes so the view does not jump away while the user looks at it.
    private func selectHole(_ index: Int, _ round: Round) {
        if !round.isActive {
            if index == shownHoleIndex(round) {
                panToHole()
            } else {
                viewingHoleIndex = index
            }
        } else if index == round.currentHoleIndex {
            if viewingHoleIndex == nil {
                panToHole()
            } else {
                resumeRound()
            }
        } else {
            holeAdvancer.pause()
            viewingHoleIndex = index
        }
    }

    /// Goes back to the round's current hole and resumes automatic hole changes.
    private func resumeRound() {
        viewingHoleIndex = nil
        holeAdvancer.resume()
    }

    /// Makes the shown hole the round's current hole and resumes automatic hole changes.
    /// Only offered for a hole after the current one: golf is played in order.
    private func playViewingHole(_ round: Round) {
        if let viewingHoleIndex {
            roundStore.startHole(viewingHoleIndex, roundID: round.id, source: .playHole)
        }
        resumeRound()
    }

    /// "Par 4 - 156 yds", or whichever part is known. Nil past the course's last hole.
    /// A past round shows the par only, since the yards are from the player's location.
    private func holeSummary(_ round: Round) -> String? {
        guard let courseHole = round.courseHole(at: shownHoleIndex(round)) else { return nil }
        let par = "Par \(courseHole.par)"
        guard round.isActive, let yards = yardsToGreenCenter(round) else { return par }
        return "\(par) - \(yards) yds"
    }

    // MARK: - Key information

    private func yardsToGreenCenter(_ round: Round) -> Int? {
        guard let courseHole = round.courseHole(at: shownHoleIndex(round)),
              let green = courseHole.green(from: round.course.features),
              let location = locationManager.lastLocation else { return nil }
        return Int(DistanceCalculator.yards(from: location, to: green.center.clLocation))
    }

    /// Feet up (+) or down (-) from the player to the center of the green.
    private func feetToGreenCenter(_ round: Round) -> Int? {
        guard let courseHole = round.courseHole(at: shownHoleIndex(round)),
              let green = courseHole.green(from: round.course.features),
              let greenElevation = green.center.elevation,
              let location = locationManager.lastLocation,
              location.verticalAccuracy >= 0 else { return nil }
        return Int(((greenElevation - location.altitude) * 3.28084).rounded())
    }

    private func keyInformation(_ round: Round) -> some View {
        let feet = feetToGreenCenter(round)
        return VStack(spacing: 8) {
            keyInformationBox(value: yardsToGreenCenter(round).map(String.init) ?? "—",
                              caption: "yds to center",
                              identifier: "DistanceToCenter")
            keyInformationBox(value: feet.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "—",
                              caption: "ft elevation",
                              identifier: "ElevationChange")
        }
        .padding(.trailing, 12)
        .padding(.top, 12)
    }

    private func keyInformationBox(value: String, caption: String, identifier: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 84)
        .padding(.vertical, 8)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Hazards

    /// Bunkers and water between the player and the green on the current hole.
    private func hazardsAhead(_ round: Round) -> [FeatureDistance] {
        guard round.isActive,
              let courseHole = round.courseHole(at: shownHoleIndex(round)),
              let green = courseHole.green(from: round.course.features),
              let location = locationManager.lastLocation else { return [] }
        return DistanceCalculator.featuresAhead(from: location, features: round.course.features(for: courseHole), green: green, limit: .max)
    }

    /// The bubbles are drawn over the map rather than as map annotations, because an annotation
    /// swallows touches and would block a long press that adds a stroke underneath it.
    private func hazardBubbles(_ round: Round, proxy: MapProxy) -> some View {
        // Reading the counter redraws the bubbles as the camera moves
        _ = cameraChanges
        return ZStack {
            ForEach(hazardsAhead(round)) { hazard in
                if let point = proxy.convert(hazard.nearestPoint.clCoordinate, to: .local) {
                    hazardBubble(yards: hazard.distanceYards)
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

    /// A small white bubble whose arrow tip sits on the start of the hazard.
    private func hazardBubble(yards: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(yards)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white))
            BubbleArrow()
                .fill(.white)
                .frame(width: 8, height: 5)
        }
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hazard in \(yards) yards")
    }

    /// Edit at the bottom left, and the map buttons at the right. While another hole is shown,
    /// "Resume round" and "Play hole" join Edit.
    private func buttonBar(_ round: Round) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                isEditing.toggle()
                refreshSuggestions()
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

            if round.isActive, let viewingHoleIndex {
                Button("Resume round") {
                    resumeRound()
                }
                .modifier(BarButtonStyle(horizontalPadding: 16))

                if viewingHoleIndex > round.currentHoleIndex {
                    Button("Play hole") {
                        playViewingHole(round)
                    }
                    .modifier(BarButtonStyle(horizontalPadding: 16))
                }
            }

            Spacer(minLength: 0)

            mapButtons(round)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    /// Hole times (only while editing), and following the player's location (only during a round).
    private func mapButtons(_ round: Round) -> some View {
        VStack(spacing: 8) {
            if isEditing {
                holeTimesButton
                    .font(.title3)
                    .padding(14)
                    .background(.thickMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }

            if round.isActive {
                locationButton
            }
        }
    }

    private var locationButton: some View {
        Button {
            followsUserLocation = true
            if let location = locationManager.lastLocation {
                if let heading = shownHoleHeading() {
                    position = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 600, heading: heading, pitch: 0))
                } else {
                    position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
                }
            }
        } label: {
            Image(systemName: followsUserLocation ? "location.fill" : "location")
                .font(.title3)
                .foregroundStyle(.blue)
                .padding(14)
                .background(.thickMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
    }

    /// Opens the list of when each hole started.
    private var holeTimesButton: some View {
        Button {
            showHoleTimes = true
        } label: {
            Image(systemName: "clock")
        }
        .accessibilityLabel("Hole times")
    }

    private func spotEditSheet(_ round: Round) -> some View {
        let strokeCount: Int = {
            guard let stroke = selectedStroke,
                  let holeIdx = round.holeIndex(containing: stroke.id) else {
                return round.hole(at: shownHoleIndex(round)).strokes.count
            }
            return round.holes[holeIdx].strokes.count
        }()

        return NavigationStack {
            VStack(spacing: 24) {
                Stepper("Spot: \(newSpotIndex + 1)", value: $newSpotIndex, in: 0...(max(strokeCount - 1, 0)))
                    .font(.title3)
                    .padding(.horizontal)

                if let stroke = selectedStroke {
                    Divider()

                    if stroke.type == .regular {
                        Button {
                            roundStore.setStrokeType(strokeID: stroke.id, type: .penalty, in: round.id)
                            selectedStroke = nil
                        } label: {
                            Label("Penalty stroke", systemImage: "exclamationmark.triangle.fill")
                        }
                        .tint(.red)
                        .accessibilityIdentifier("StrokePenalty")

                        Button {
                            roundStore.setStrokeType(strokeID: stroke.id, type: .outOfBounds, in: round.id)
                            selectedStroke = nil
                        } label: {
                            Label("Out of bounds", systemImage: "xmark.circle.fill")
                        }
                        .accessibilityIdentifier("StrokeOutOfBounds")
                    } else {
                        Button {
                            roundStore.setStrokeType(strokeID: stroke.id, type: .regular, in: round.id)
                            selectedStroke = nil
                        } label: {
                            Label("Clear penalty", systemImage: "arrow.uturn.backward.circle")
                        }
                        .accessibilityIdentifier("ClearPenalty")
                    }
                }

                Button("Delete Spot", role: .destructive) {
                    showDeleteConfirm = true
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Edit Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selectedStroke = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let stroke = selectedStroke {
                            roundStore.reorderStroke(stroke, to: newSpotIndex, in: round.id)
                        }
                        selectedStroke = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func shownHoleHeading() -> Double? {
        guard let round, let courseHole = round.courseHole(at: shownHoleIndex(round)),
              let green = courseHole.green(from: round.course.features),
              let firstTeeID = courseHole.tees.values.first,
              let teeFeature = round.course.findFeature(id: firstTeeID) else { return nil }
        return Self.bearing(from: teeFeature.center, to: green.center)
    }

    private func panToHole() {
        guard let round, let courseHole = round.courseHole(at: shownHoleIndex(round)),
              let green = courseHole.green(from: round.course.features) else { return }
        let course = round.course

        let holeFeatures = course.features(for: courseHole)
        let allCoords = holeFeatures.flatMap(\.polygon)
        guard !allCoords.isEmpty else { return }

        let minLat = allCoords.map(\.latitude).min()!
        let maxLat = allCoords.map(\.latitude).max()!
        let minLon = allCoords.map(\.longitude).min()!
        let maxLon = allCoords.map(\.longitude).max()!
        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2

        // Bearing from tee to green → heading so green is at top
        let teeCenter: Coordinate
        if let firstTeeID = courseHole.tees.values.first,
           let teeFeature = course.findFeature(id: firstTeeID) {
            teeCenter = teeFeature.center
        } else {
            teeCenter = Coordinate(latitude: midLat, longitude: midLon)
        }
        let heading = Self.bearing(from: teeCenter, to: green.center)

        // Offset center towards the tee so the user's location (near tee)
        // appears above the button bar instead of hidden behind it
        let headingRad = heading * .pi / 180
        let offsetFraction = 0.08 // shift 8% of hole length towards tee
        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        let center = CLLocationCoordinate2D(
            latitude: midLat - cos(headingRad) * latSpan * offsetFraction,
            longitude: midLon - sin(headingRad) * lonSpan * offsetFraction
        )

        // Camera distance: must show all features + padding from the offset center.
        // Compute the farthest point from center, then double (center→edge is half the view).
        let padMeters = 18.3 // ~20 yards
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let farthest = allCoords.map { centerLoc.distance(from: $0.clLocation) }.max() ?? 0
        let cameraDistance = (farthest + padMeters) * 3.5

        followsUserLocation = false
        position = .camera(MapCamera(centerCoordinate: center, distance: cameraDistance, heading: heading, pitch: 0))
    }

    private static func bearing(from start: Coordinate, to end: Coordinate) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Stroke Suggestions

    /// Loads the watch's GPS track for the hole being viewed and recomputes suggestions.
    /// A fix belongs to the hole the timeline says was being played at its time.
    private func reloadTrack() {
        guard let round else {
            roundTrack = []
            holeTrack = []
            suggestions = []
            return
        }
        roundTrack = streamStore.points(for: round.id, until: round.endedAt)
        let holeIndex = shownHoleIndex(round)
        holeTrack = roundTrack.filter { round.holeIndex(at: $0.timestamp) == holeIndex }
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        guard let round, isEditing else {
            suggestions = []
            return
        }
        suggestions = StrokeFinder.suggestions(
            in: round,
            holeIndex: shownHoleIndex(round),
            points: roundTrack,
            swings: streamStore.swings(for: round.id, until: round.endedAt),
            minStop: settingsStore.settings.stationaryThreshold,
            hidden: suggestionStore.hiddenIDs(for: round.id)
        )
    }

    /// A pin with a plus sign. Tapping converts the suggestion into a real stroke.
    private func suggestionPin(_ suggestion: StrokeSuggestion, round: Round) -> some View {
        Button {
            convertSuggestion(suggestion, round: round)
        } label: {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                BubbleArrow()
                    .fill(Color.green)
                    .frame(width: 10, height: 7)
            }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add suggested stroke")
    }

    private func convertSuggestion(_ suggestion: StrokeSuggestion, round: Round) {
        guard let coordinate = suggestion.coordinate else { return }
        let stroke = Stroke(coordinate: coordinate)
        // Both computed before the add, so they describe the strokes the new one joins
        let holeIndex = shownHoleIndex(round)
        let strokes = round.hole(at: holeIndex).strokes
        let insertAt = insertionIndex(for: suggestion.timestamp, in: strokes)
        let appending = insertAt == strokes.count
        roundStore.addStroke(to: round.id, holeIndex: holeIndex, stroke: stroke)
        if !appending {
            roundStore.reorderStroke(stroke, to: insertAt, in: round.id)
        }
        suggestionStore.hide(suggestion.id, roundID: round.id)
    }

    /// Where a stroke hit at `timestamp` goes among a hole's strokes: before the first one that
    /// was probably hit later, going by the hole's GPS.
    private func insertionIndex(for timestamp: Date, in strokes: [Stroke]) -> Int {
        strokes.firstIndex { stroke in
            StrokeFinder.estimatedTime(of: stroke, in: holeTrack).map { timestamp < $0 } ?? false
        } ?? strokes.count
    }
}

/// The look of the Edit button: a capsule on a thick material with a shadow.
private struct BarButtonStyle: ViewModifier {
    let horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 12)
            .background(.thickMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

/// A triangle pointing down.
private struct BubbleArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
