import SwiftUI
import MapKit

struct RoundMapView: View {
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)

    let roundID: UUID
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager

    private var round: Round {
        roundStore.rounds.first(where: { $0.id == roundID })!
    }

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedMark: BallMark?
    @State private var showDeleteConfirm = false
    @State private var draggingMark: BallMark?
    @State private var dragOffset: CGSize = .zero
    @State private var newSpotIndex: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            mapView
            overlayView
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(round.formattedDate)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { selectedMark != nil && !showDeleteConfirm },
            set: { if !$0 && !showDeleteConfirm { selectedMark = nil } }
        )) {
            spotEditSheet
        }
        .onAppear {
            locationManager.startUpdating()
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .onReceive(locationManager.$lastLocation) { location in
            guard let location else { return }
            position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
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

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $position) {
                ForEach(Array(round.marks.enumerated()), id: \.element.id) { index, mark in
                    Annotation("", coordinate: mark.coordinate) {
                        spotMarker(index: index, mark: mark, proxy: proxy)
                    }
                }
                UserAnnotation()
            }
            .mapControls {
                MapCompass()
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

    private func spotMarker(index: Int, mark: BallMark, proxy: MapProxy) -> some View {
        let isDragging = draggingMark?.id == mark.id
        return Circle()
            .fill(isDragging ? Color.orange : Color(.systemBackground))
            .frame(width: 28, height: 28)
            .overlay {
                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(isDragging ? .white : .primary)
            }
            .shadow(radius: isDragging ? 4 : 2)
            .offset(isDragging ? dragOffset : .zero)
            .onTapGesture {
                if let index = round.marks.firstIndex(where: { $0.id == mark.id }) {
                    newSpotIndex = index
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

    private var overlayView: some View {
        VStack {
            statsBar
            Spacer()
            if round.isActive {
                buttonBar
            }
        }
    }

    @ViewBuilder
    private var statsBar: some View {
        if !round.marks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let lastMark = round.marks.last,
                   let location = locationManager.lastLocation {
                    let yards = Int(location.distance(from: lastMark.location) * 1.09361)
                    Text("Previous: \(yards) yds")
                        .font(.headline)
                }
                Text("Strokes: \(max(round.marks.count - 1, 0))")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
    }

    private var buttonBar: some View {
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
                        if let location = locationManager.lastLocation {
                            position = .region(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan))
                        }
                    } label: {
                        Image(systemName: "location.fill")
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
        .padding(.bottom, 32)
    }

    private var spotEditSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Stepper("Spot: \(newSpotIndex)", value: $newSpotIndex, in: 0...(max(round.marks.count - 1, 0)))
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
