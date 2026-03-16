import SwiftUI
import MapKit
import CourseData

struct RoundMapView: View {
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)

    let roundID: UUID
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager
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
            if followsUserLocation, let location {
                position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
            }
            if let round, let selection = round.courseSelection, !holeAdvancer.isPaused, let location {
                if let detected = HoleAdvancer.detectHole(location: location, courseSelection: selection),
                   detected != round.currentHoleIndex {
                    roundStore.setHoleIndex(detected)
                }
            }
        }
        .onChange(of: roundStore.rounds) {
            if round == nil {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func roundContent(_ round: Round) -> some View {
        ZStack(alignment: .top) {
            mapView(round)
            overlayView(round)
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    if let courseName = round.courseSelection?.course.name {
                        Text("\(courseName) on \(round.date.formatted(date: .long, time: .omitted))")
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(round.date.formatted(date: .long, time: .omitted))
                            .font(.headline)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
            }
            .mapControls {
                MapCompass()
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
            informationPanel(round)
            Spacer()
            if round.isActive {
                buttonBar(round)
            }
        }
    }

    @ViewBuilder
    private func informationPanel(_ round: Round) -> some View {
        if round.isActive {
            VStack(spacing: 6) {
                if let courseHole = round.currentCourseHole,
                   let course = round.courseSelection?.course,
                   let green = courseHole.green(from: course.features),
                   let location = locationManager.lastLocation {
                    let direction: Vector2D = courseHole.vector(for: green.id, from: course.features)
                        ?? Vector2D(
                            dx: green.center.latitude - location.coordinate.latitude,
                            dy: green.center.longitude - location.coordinate.longitude
                        ).normalized()
                    let greenDist = DistanceCalculator.greenDistances(from: location, green: green, direction: direction)
                    let holeFeatures = course.features(for: courseHole)
                    let features = DistanceCalculator.featuresAhead(from: location, features: holeFeatures, green: green)

                    Text("Par \(courseHole.par)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        distanceLabel("Front", greenDist.front)
                        distanceLabel("Mid", greenDist.middle)
                        distanceLabel("Back", greenDist.back)
                    }

                    Divider()

                    let detailItems = detailRows(round: round, features: features)
                    detailGrid(detailItems)
                } else {
                    detailGrid(detailRows(round: round, features: []))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("InformationPanel")
        } else if !round.allMarks.isEmpty {
            Text("\(round.holes.count) hole\(round.holes.count == 1 ? "" : "s") · \(round.allMarks.count) mark\(round.allMarks.count == 1 ? "" : "s")")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
        }
    }

    private func distanceLabel(_ label: String, _ yards: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(yards)")
                .font(.body)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private struct DetailRow: Identifiable {
        let id = UUID()
        let left: DetailItem
        let right: DetailItem?
    }

    private struct DetailItem {
        let icon: String?
        let iconColor: Color?
        let label: String
        let value: String
    }

    private func detailRows(round: Round, features: [FeatureDistance]) -> [DetailRow] {
        var items: [DetailItem] = [
            DetailItem(icon: nil, iconColor: nil, label: "Previous", value: previousDistance(round)),
            DetailItem(icon: nil, iconColor: nil, label: "Strokes", value: "\(round.currentHole.strokeCount)")
        ]
        for fd in features {
            items.append(DetailItem(
                icon: fd.feature.type == .water ? "drop.fill" : "square.fill",
                iconColor: fd.feature.type == .water ? .blue : .yellow,
                label: fd.feature.type.rawValue.capitalized,
                value: "\(fd.distanceYards) yds"
            ))
        }
        var rows: [DetailRow] = []
        for i in stride(from: 0, to: items.count, by: 2) {
            rows.append(DetailRow(left: items[i], right: i + 1 < items.count ? items[i + 1] : nil))
        }
        return rows
    }

    private func detailGrid(_ rows: [DetailRow]) -> some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    detailCell(row.left)
                    if let right = row.right {
                        detailCell(right)
                    } else {
                        Spacer().frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func detailCell(_ item: DetailItem) -> some View {
        HStack(spacing: 4) {
            if let icon = item.icon, let color = item.iconColor {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(color)
            }
            Text(item.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(item.value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private func previousDistance(_ round: Round) -> String {
        if let lastMark = round.marks.last,
           let location = locationManager.lastLocation {
            return DistanceCalculator.formattedYards(from: location, to: lastMark.location)
        }
        return "0 yds"
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
                    followsUserLocation = true
                    if let location = locationManager.lastLocation {
                        position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }

            HStack(spacing: 16) {
                Button {
                    holeAdvancer.pause()
                    roundStore.previousHole()
                    panToCurrentTee()
                } label: {
                    Label("Prev", systemImage: "chevron.left")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(round.currentHoleIndex == 0)

                Text("Hole \(round.currentHoleNumber)")
                    .font(.headline)
                    .accessibilityIdentifier("Hole \(round.currentHoleNumber)")

                Button {
                    holeAdvancer.pause()
                    roundStore.nextHole()
                    panToCurrentTee()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(round.holes.count >= 18 && round.currentHoleIndex == round.holes.count - 1)
            }

            HStack {
                Spacer()

                Button(action: markBall) {
                    Label("At my ball", systemImage: "mappin.and.ellipse")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Spacer()
                    .overlay(alignment: .leading) {
                        Button {
                            followsUserLocation = true
                            if let location = locationManager.lastLocation {
                                position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
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
                        .padding(.leading, 16)
                    }
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

    private func markBall() {
        guard let location = locationManager.lastLocation else { return }
        let mark = BallMark(coordinate: location.coordinate)
        roundStore.addMark(mark)
    }

    private func panToCurrentTee() {
        guard let round, let courseHole = round.currentCourseHole,
              let course = round.courseSelection?.course,
              let firstTeeID = courseHole.tees.values.first,
              let teeFeature = course.findFeature(id: firstTeeID) else { return }
        followsUserLocation = false
        position = .region(MKCoordinateRegion(center: teeFeature.center.clCoordinate, span: Self.defaultSpan))
    }
}
