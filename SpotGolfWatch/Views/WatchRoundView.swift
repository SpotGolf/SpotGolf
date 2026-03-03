import SwiftUI
import CoreLocation

struct WatchRoundView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var showSwingAway = false
    @State private var swingAwayTask: Task<Void, Never>?

    private var liveDistance: String? {
        guard let location = locationManager.lastLocation,
              let lastMark = roundStore.activeRound?.marks.last else { return nil }
        return DistanceCalculator.formattedYards(from: location, to: lastMark.location)
    }

    var body: some View {
        Group {
            if showSwingAway {
                Text("Swing away")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    if let round = roundStore.activeRound {
                        Text("Previous: \(liveDistance ?? previousDistance(round: round))")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text("Strokes: \(max(round.marks.count - 1, 0))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(action: markBall) {
                            Label("At my ball", systemImage: "mappin.and.ellipse")
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button("End Round", role: .destructive) {
                            locationManager.stopUpdating()
                            roundStore.endRound()
                        }
                        .font(.caption)
                    } else {
                        Text("No active round")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Button("Start Round") {
                            roundStore.startRound()
                            locationManager.startUpdating()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            if roundStore.activeRound != nil {
                locationManager.startUpdating()
            }
        }
        .onDisappear {
            locationManager.stopUpdating()
            swingAwayTask?.cancel()
        }
    }

    private func previousDistance(round: Round) -> String {
        if round.marks.count >= 2 {
            let last = round.marks[round.marks.count - 1]
            let prev = round.marks[round.marks.count - 2]
            return DistanceCalculator.formattedYards(from: prev, to: last)
        }
        return "0 yds"
    }

    private func markBall() {
        swingAwayTask?.cancel()
        guard let location = locationManager.lastLocation else { return }
        let mark = BallMark(coordinate: location.coordinate)
        roundStore.addMark(mark)

        showSwingAway = true
        swingAwayTask = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            showSwingAway = false
        }
    }
}
