import SwiftUI
import CoreLocation

struct WatchRoundView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var showSwingAway = false
    @State private var liveDistance: String?
    @State private var distanceTimer: Timer?

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
                            stopDistanceTimer()
                            roundStore.endRound()
                        }
                        .font(.caption)
                    } else {
                        Text("No active round")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Button("Start Round") {
                            roundStore.startRound()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding()
            }
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

    private func startDistanceTimer() {
        stopDistanceTimer()
        liveDistance = "0 yds"
        distanceTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task { @MainActor in
                updateLiveDistance()
            }
        }
    }

    private func stopDistanceTimer() {
        distanceTimer?.invalidate()
        distanceTimer = nil
        liveDistance = nil
    }

    private func updateLiveDistance() {
        locationManager.requestLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let location = locationManager.lastLocation,
                  let lastMark = roundStore.activeRound?.marks.last else { return }
            let meters = location.distance(from: lastMark.location)
            let yards = Int(meters * 1.09361)
            liveDistance = "\(yards) yds"
        }
    }

    private func markBall() {
        stopDistanceTimer()
        locationManager.requestLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let location = locationManager.lastLocation else { return }
            let mark = BallMark(coordinate: location.coordinate)
            roundStore.addMark(mark)

            showSwingAway = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                showSwingAway = false
                startDistanceTimer()
            }
        }
    }
}
