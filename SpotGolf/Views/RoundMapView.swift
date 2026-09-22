import SwiftUI
import MapKit
import CourseData

struct RoundMapView: View {
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)

    let roundID: UUID
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var guessStore: GuessStore
    @EnvironmentObject var syncService: SyncService
    @Environment(\.dismiss) private var dismiss

    private var round: Round? {
        roundStore.rounds.first(where: { $0.id == roundID })
    }

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var followsUserLocation = true
    @State private var selectedMark: BallMark?
    @State private var showDeleteConfirm = false
    @State private var draggingMark: BallMark?
    @State private var dragOffset: CGSize = .zero
    @State private var newSpotIndex: Int = 0
    @State private var holeAdvancer = HoleAdvancer()
    @State private var hasInitialPan = false
    @State private var pendingPanToHole = false
    @State private var showGhostPins = true
    @State private var selectedGuess: MissedMarkGuess?
    @State private var guessSpotIndex: Int = 0
    @State private var showClearGuessesConfirm = false
    @State private var cameraChanges = 0

    var body: some View {
        Group {
            if let round {
                roundContent(round)
            }
        }
        .onAppear {
            locationManager.startUpdating()
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .onReceive(locationManager.$lastLocation) { location in
            if !hasInitialPan, location != nil, round?.courseSelection != nil {
                hasInitialPan = true
                panToHole()
            } else if followsUserLocation, let location {
                if let heading = currentHoleHeading() {
                    position = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 600, heading: heading, pitch: 0))
                } else {
                    position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
                }
            }
            if let round, let selection = round.courseSelection, !holeAdvancer.isPaused, let location {
                if let detected = HoleAdvancer.detectHole(location: location, courseSelection: selection, currentHoleIndex: round.currentHoleIndex) {
                    roundStore.setHoleIndex(detected)
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
        }
        .onChange(of: round?.currentHoleIndex) {
            // Also covers a hole chosen on the watch
            panToHole()
        }
    }

    @ViewBuilder
    private func roundContent(_ round: Round) -> some View {
        VStack(spacing: 0) {
            if round.isActive {
                holeHeader(round)
            }
            ZStack(alignment: .top) {
                mapView(round)
                overlayView(round)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(round.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // During a round the header has its own back button, so the bar and its title are hidden
        .toolbar(round.isActive ? .hidden : .visible, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { selectedMark != nil && !showDeleteConfirm },
            set: { if !$0 && !showDeleteConfirm { selectedMark = nil } }
        )) {
            spotEditSheet(round)
        }
        .alert("Delete Spot", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let mark = selectedMark {
                    roundStore.removeMark(mark, from: round.id)
                }
                selectedMark = nil
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirm = false
            }
        } message: {
            Text("Are you sure you want to delete this spot?")
        }
        .sheet(isPresented: Binding(
            get: { selectedGuess != nil },
            set: { if !$0 { selectedGuess = nil } }
        )) {
            guessEditSheet(round)
        }
        .alert("Delete All Missed Mark Guesses", isPresented: $showClearGuessesConfirm) {
            Button("Delete All", role: .destructive) {
                guessStore.clearHole(roundID: round.id, holeIndex: round.currentHoleIndex)
                syncService.send(.clearGuesses(round.id, round.currentHoleIndex))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete all Missed Mark Guesses for this hole?")
        }
    }

    private func mapView(_ round: Round) -> some View {
        let marksToShow = round.isActive ? round.marks : round.allMarks
        return MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                ForEach(Array(marksToShow.enumerated()), id: \.element.id) { index, mark in
                    let displayIndex = round.isActive ? index : allMarksDisplayIndex(mark: mark, round: round)
                    Annotation("", coordinate: mark.coordinate) {
                        spotMarker(index: displayIndex, mark: mark, round: round, proxy: proxy)
                    }
                }
                if showGhostPins {
                    let currentGuesses = guessStore.guesses(for: round.id, holeIndex: round.currentHoleIndex)
                    ForEach(currentGuesses) { guess in
                        Annotation("", coordinate: guess.coordinate) {
                            ghostPinMarker(guess: guess)
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
                            guard round.isActive, let drag,
                                  let coordinate = proxy.convert(drag.location, from: .global) else { return }
                            let mark = BallMark(coordinate: coordinate)
                            newSpotIndex = round.marks.count // capture before append
                            roundStore.addMark(mark)
                            selectedMark = mark
                        default:
                            break
                        }
                    }
            )
        }
    }

    /// For past rounds, compute the 1-based index within the mark's own hole.
    private func allMarksDisplayIndex(mark: BallMark, round: Round) -> Int {
        guard let holeIdx = round.holeIndex(containing: mark.id) else { return 0 }
        let hole = round.holes[holeIdx]
        return hole.marks.firstIndex(where: { $0.id == mark.id }) ?? 0
    }

    private static let dragLiftOffset: CGFloat = -30

    private func markColor(for type: BallMarkType) -> Color {
        switch type {
        case .regular: return .blue
        case .penalty: return .red
        case .outOfBounds: return .white
        }
    }

    private func spotMarker(index: Int, mark: BallMark, round: Round, proxy: MapProxy) -> some View {
        let isDragging = draggingMark?.id == mark.id
        let pinColor = markColor(for: mark.type)
        let textColor: Color = mark.type == .outOfBounds ? .black : .white
        return VStack(spacing: 0) {
            Button {
                if let holeIdx = round.holeIndex(containing: mark.id) {
                    let hole = round.holes[holeIdx]
                    if let markIdx = hole.marks.firstIndex(where: { $0.id == mark.id }) {
                        newSpotIndex = markIdx
                    }
                }
                selectedMark = mark
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
                        if !isDragging && mark.type == .outOfBounds {
                            Circle().stroke(Color.gray, lineWidth: 1.5)
                        }
                    }
                    .shadow(color: isDragging ? .orange.opacity(0.4) : .black.opacity(0.2),
                            radius: isDragging ? 8 : 2, y: isDragging ? 2 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("SpotMark_\(index + 1)")

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
                    switch value {
                    case .second(true, let drag):
                        if draggingMark == nil {
                            withAnimation(.easeOut(duration: 0.15)) {
                                draggingMark = mark
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
                    switch value {
                    case .second(true, let drag):
                        if let drag,
                           let coordinate = proxy.convert(drag.location, from: .global) {
                            roundStore.moveMark(mark, to: coordinate, in: round.id)
                        }
                    default:
                        break
                    }
                    draggingMark = nil
                    dragOffset = .zero
                }
        )
    }

    private func overlayView(_ round: Round) -> some View {
        VStack {
            if round.isActive {
                HStack {
                    Spacer()
                    keyInformation(round)
                }
            } else if !round.allMarks.isEmpty {
                Text("\(round.holes.count) hole\(round.holes.count == 1 ? "" : "s") · \(round.allMarks.count) mark\(round.allMarks.count == 1 ? "" : "s")")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
            }
            Spacer()
            if round.isActive {
                buttonBar(round)
            }
        }
    }

    // MARK: - Header

    /// A back button, then every hole as a circle. The current hole's par and distance sit underneath.
    private func holeHeader(_ round: Round) -> some View {
        let holeCount = round.courseSelection?.orderedHoles.count ?? Round.maxHoles
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .accessibilityLabel("Back")

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<holeCount, id: \.self) { index in
                                holeCircle(index, round)
                                    .id(index)
                            }
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 16)
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        proxy.scrollTo(round.currentHoleIndex, anchor: .center)
                    }
                    .onChange(of: round.currentHoleIndex) {
                        withAnimation {
                            proxy.scrollTo(round.currentHoleIndex, anchor: .center)
                        }
                    }
                }
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

    private func holeCircle(_ index: Int, _ round: Round) -> some View {
        let isCurrent = index == round.currentHoleIndex
        let isPlayed = index < round.holes.count && !round.holes[index].marks.isEmpty
        return Button {
            selectHole(index, round)
        } label: {
            Text("\(index + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isCurrent ? Color.green : isPlayed ? Color.green.opacity(0.18) : Color.clear))
                .overlay(Circle().stroke(isCurrent ? Color.green : Color.secondary.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hole \(index + 1)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// Goes to a hole by hand, which pauses automatic hole changes.
    private func selectHole(_ index: Int, _ round: Round) {
        holeAdvancer.pause()
        if index == round.currentHoleIndex {
            panToHole()
        } else {
            pendingPanToHole = true
            roundStore.setHoleIndex(index)
        }
    }

    /// "Par 4 - 156 yds", or whichever part is known. Nil without a course.
    private func holeSummary(_ round: Round) -> String? {
        guard let courseHole = round.currentCourseHole else { return nil }
        let par = "Par \(courseHole.par)"
        guard let yards = yardsToGreenCenter(round) else { return par }
        return "\(par) - \(yards) yds"
    }

    // MARK: - Key information

    private func yardsToGreenCenter(_ round: Round) -> Int? {
        guard let courseHole = round.currentCourseHole,
              let course = round.courseSelection?.course,
              let green = courseHole.green(from: course.features),
              let location = locationManager.lastLocation else { return nil }
        return Int(DistanceCalculator.yards(from: location, to: green.center.clLocation))
    }

    /// Feet up (+) or down (-) from the player to the center of the green.
    private func feetToGreenCenter(_ round: Round) -> Int? {
        guard let courseHole = round.currentCourseHole,
              let course = round.courseSelection?.course,
              let green = courseHole.green(from: course.features),
              let greenElevation = green.center.elevation,
              let location = locationManager.lastLocation,
              location.verticalAccuracy >= 0 else { return nil }
        return Int(((greenElevation - location.altitude) * 3.28084).rounded())
    }

    @ViewBuilder
    private func keyInformation(_ round: Round) -> some View {
        if round.courseSelection != nil {
            let feet = feetToGreenCenter(round)
            VStack(spacing: 8) {
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
              let courseHole = round.currentCourseHole,
              let course = round.courseSelection?.course,
              let green = courseHole.green(from: course.features),
              let location = locationManager.lastLocation else { return [] }
        return DistanceCalculator.featuresAhead(from: location, features: course.features(for: courseHole), green: green, limit: .max)
    }

    /// The bubbles are drawn over the map rather than as map annotations, because an annotation
    /// swallows touches and would block a long press that adds a mark underneath it.
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

    private func buttonBar(_ round: Round) -> some View {
        VStack(spacing: 12) {
            if holeAdvancer.isPaused && round.courseSelection != nil {
                Button("Resume round") {
                    holeAdvancer.resume()
                    if let round = self.round, let selection = round.courseSelection,
                       let location = locationManager.lastLocation,
                       let detected = HoleAdvancer.nearestHole(location: location, courseSelection: selection) {
                        roundStore.setHoleIndex(detected)
                    }
                    pendingPanToHole = true
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }

            HStack {
                Spacer()

                VStack(spacing: 8) {
                    Button {
                        followsUserLocation = true
                        if let location = locationManager.lastLocation {
                            if let heading = currentHoleHeading() {
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

                    if hasGuessesForCurrentHole(round) {
                        Button {
                            showGhostPins.toggle()
                        } label: {
                            Image(systemName: showGhostPins ? "eye.fill" : "eye.slash")
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .padding(14)
                                .background(.thickMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        }

                        Button {
                            showClearGuessesConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.title3)
                                .foregroundStyle(.red)
                                .padding(14)
                                .background(.thickMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        }
                    }
                }
                .padding(.trailing, 16)
            }
        }
        .padding(.bottom, 32)
    }

    private func spotEditSheet(_ round: Round) -> some View {
        let markCount: Int = {
            guard let mark = selectedMark,
                  let holeIdx = round.holeIndex(containing: mark.id) else {
                return round.marks.count
            }
            return round.holes[holeIdx].marks.count
        }()

        return NavigationStack {
            VStack(spacing: 24) {
                Stepper("Spot: \(newSpotIndex + 1)", value: $newSpotIndex, in: 0...(max(markCount - 1, 0)))
                    .font(.title3)
                    .padding(.horizontal)

                if round.isActive, let mark = selectedMark {
                    Divider()

                    if mark.type == .regular {
                        Button {
                            roundStore.setMarkType(markID: mark.id, type: .penalty, in: round.id)
                            selectedMark = nil
                        } label: {
                            Label("Mark as penalty", systemImage: "exclamationmark.triangle.fill")
                        }
                        .tint(.red)
                        .accessibilityIdentifier("MarkAsPenalty")

                        Button {
                            roundStore.setMarkType(markID: mark.id, type: .outOfBounds, in: round.id)
                            selectedMark = nil
                        } label: {
                            Label("Mark out of bounds", systemImage: "xmark.circle.fill")
                        }
                        .accessibilityIdentifier("MarkOutOfBounds")
                    } else {
                        Button {
                            roundStore.setMarkType(markID: mark.id, type: .regular, in: round.id)
                            selectedMark = nil
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
                        selectedMark = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let mark = selectedMark {
                            roundStore.reorderMark(mark, to: newSpotIndex, in: round.id)
                        }
                        selectedMark = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func currentHoleHeading() -> Double? {
        guard let round, let courseHole = round.currentCourseHole,
              let course = round.courseSelection?.course,
              let green = courseHole.green(from: course.features),
              let firstTeeID = courseHole.tees.values.first,
              let teeFeature = course.findFeature(id: firstTeeID) else { return nil }
        return Self.bearing(from: teeFeature.center, to: green.center)
    }

    private func panToHole() {
        guard let round, let courseHole = round.currentCourseHole,
              let course = round.courseSelection?.course,
              let green = courseHole.green(from: course.features) else { return }

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

    // MARK: - Ghost Pin Edit Sheet

    private func guessEditSheet(_ round: Round) -> some View {
        let markCount = round.currentHole.marks.count
        return NavigationStack {
            VStack(spacing: 24) {
                Text("Missed Mark Guess")
                    .font(.headline)

                Stepper("Insert at position: \(guessSpotIndex + 1)", value: $guessSpotIndex, in: 0...markCount)
                    .font(.title3)
                    .padding(.horizontal)

                Button {
                    if let guess = selectedGuess {
                        let mark = BallMark(coordinate: guess.coordinate, timestamp: guess.timestamp)
                        roundStore.addMark(to: round.id, holeIndex: guess.holeIndex, mark: mark)
                        if guessSpotIndex < round.currentHole.marks.count - 1 {
                            roundStore.reorderMark(mark, to: guessSpotIndex, in: round.id)
                        }
                        guessStore.remove(guessID: guess.id, roundID: round.id)
                        syncService.send(.removeGuess(guess.id, round.id))
                    }
                    selectedGuess = nil
                } label: {
                    Label("My ball was here", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)

                Button {
                    if let guess = selectedGuess {
                        guessStore.remove(guessID: guess.id, roundID: round.id)
                        syncService.send(.removeGuess(guess.id, round.id))
                    }
                    selectedGuess = nil
                } label: {
                    Label("Ignore", systemImage: "xmark.circle")
                }
                .tint(.secondary)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Missed Mark Guess")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { selectedGuess = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Ghost Pins

    private func ghostPinMarker(guess: MissedMarkGuess) -> some View {
        Button {
            guessSpotIndex = bestGuessIndex(for: guess)
            selectedGuess = guess
        } label: {
            Circle()
                .strokeBorder(Color.orange, lineWidth: 2)
                .background(Circle().fill(Color.orange.opacity(0.3)))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "questionmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
        }
        .buttonStyle(.plain)
    }

    private func bestGuessIndex(for guess: MissedMarkGuess) -> Int {
        guard let round else { return 0 }
        let marks = round.currentHole.marks
        // Find the position where this guess fits chronologically
        for (i, mark) in marks.enumerated() {
            if guess.timestamp < mark.timestamp {
                return i
            }
        }
        return marks.count
    }

    private func hasGuessesForCurrentHole(_ round: Round) -> Bool {
        !guessStore.guesses(for: round.id, holeIndex: round.currentHoleIndex).isEmpty
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
