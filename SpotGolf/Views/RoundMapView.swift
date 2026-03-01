import SwiftUI
import MapKit

struct RoundMapView: View {
    let round: Round
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                ForEach(Array(round.marks.enumerated()), id: \.element.id) { index, mark in
                    Annotation("\(index + 1)", coordinate: mark.coordinate) {
                        Circle()
                            .fill(.white)
                            .frame(width: 28, height: 28)
                            .overlay {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                            .shadow(radius: 2)
                    }
                }

                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }

            if round.isActive {
                Button(action: markBall) {
                    Label("At my ball", systemImage: "mappin.and.ellipse")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(round.formattedDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if round.isActive && round.marks.count >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    let last = round.marks[round.marks.count - 1]
                    let prev = round.marks[round.marks.count - 2]
                    Text(DistanceCalculator.formattedYards(from: prev, to: last))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func markBall() {
        locationManager.requestLocation()
        // Use last known location (may be from a previous request or the one just triggered)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let location = locationManager.lastLocation else { return }
            let mark = BallMark(coordinate: location.coordinate)
            roundStore.addMark(mark)
        }
    }
}
