import SwiftUI
import Combine
import CoreLocation

struct WatchRoundView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var showSwingAway = false
    @State private var pendingMark = false
    @State private var distanceTimerActive = false
    @State private var swingAwayTask: Task<Void, Never>?

    private var liveDistance: String? {
        guard let location = locationManager.lastLocation,
              let lastMark = roundStore.activeRound?.marks.last else { return nil }
        return DistanceCalculator.formattedYards(from: location, to: lastMark.location)
    }

    private let distanceTimerPublisher = Timer.publish(every: 10, on: .main, in: .common)
    @State private var distanceTimerCancellable: Cancellable?

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
                        .disabled(pendingMark)

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
        .onReceive(locationManager.$lastLocation) { newLocation in
            guard pendingMark, let location = newLocation else { return }
            pendingMark = false
            let mark = BallMark(coordinate: location.coordinate)
            roundStore.addMark(mark)

            showSwingAway = true
            swingAwayTask = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                showSwingAway = false
                startDistanceTimer()
            }
        }
        .onReceive(distanceTimerPublisher) { _ in
            guard distanceTimerActive else { return }
            locationManager.requestLocation()
        }
        .onDisappear {
            stopDistanceTimer()
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

    private func startDistanceTimer() {
        locationManager.requestLocation()
        distanceTimerActive = true
        distanceTimerCancellable = distanceTimerPublisher.connect()
    }

    private func stopDistanceTimer() {
        distanceTimerActive = false
        distanceTimerCancellable?.cancel()
        distanceTimerCancellable = nil
    }

    private func markBall() {
        stopDistanceTimer()
        swingAwayTask?.cancel()
        pendingMark = true
        locationManager.requestLocation()
    }
}
