import SwiftUI
import MapKit

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
            guard followsUserLocation, let location else { return }
            position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
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
        .navigationTitle(round.formattedDate)
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
                ForEach(Array(marksToShow.enumerated()), id: \.element.id) { index, mark in
                    let displayIndex = round.isActive ? index : allMarksDisplayIndex(mark: mark, round: round)
                    Annotation("", coordinate: mark.coordinate) {
                        spotMarker(index: displayIndex, mark: mark, round: round, proxy: proxy)
                    }
                }
                UserAnnotation()
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
                            roundStore.addMark(mark)
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

    private func spotMarker(index: Int, mark: BallMark, round: Round, proxy: MapProxy) -> some View {
        let isDragging = draggingMark?.id == mark.id
        return Circle()
            .fill(isDragging ? Color.orange : Color(.systemBackground))
            .frame(width: 28, height: 28)
            .overlay {
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(isDragging ? .white : .primary)
            }
            .shadow(radius: isDragging ? 4 : 2)
            .offset(isDragging ? dragOffset : .zero)
            .onTapGesture {
                if let holeIdx = round.holeIndex(containing: mark.id) {
                    let hole = round.holes[holeIdx]
                    if let markIdx = hole.marks.firstIndex(where: { $0.id == mark.id }) {
                        newSpotIndex = markIdx
                    }
                }
                selectedMark = mark
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(coordinateSpace: .global))
                    .onChanged { value in
                        switch value {
                        case .second(true, let drag):
                            if draggingMark == nil {
                                draggingMark = mark
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
            statsBar(round)
            Spacer()
            if round.isActive {
                buttonBar(round)
            }
        }
    }

    @ViewBuilder
    private func statsBar(_ round: Round) -> some View {
        if round.isActive || !round.allMarks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if round.isActive {
                    Text("Hole \(round.currentHoleNumber)")
                        .font(.headline)
                        .accessibilityIdentifier("Hole \(round.currentHoleNumber)")
                    Text("Previous: \(previousDistance(round))")
                        .font(.headline)
                    Text("Strokes: \(round.currentHole.strokeCount)")
                        .font(.headline)
                } else {
                    Text("\(round.holes.count) hole\(round.holes.count == 1 ? "" : "s") · \(round.allMarks.count) mark\(round.allMarks.count == 1 ? "" : "s")")
                        .font(.headline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
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
            HStack(spacing: 16) {
                Button {
                    roundStore.previousHole()
                } label: {
                    Label("Prev Hole", systemImage: "chevron.left")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(round.currentHoleIndex == 0)

                Button {
                    roundStore.nextHole()
                } label: {
                    Label("Next Hole", systemImage: "chevron.right")
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
}
