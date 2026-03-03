import SwiftUI
import CoreLocation

struct WatchRoundView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var showSwingAway = false
    @State private var swingAwayTask: Task<Void, Never>?

    @State private var liveDistance: String?

    var body: some View {
        Group {
            if showSwingAway {
                Text("Swing away")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let round = roundStore.activeRound {
                TabView {
                    playPage(round)
                    endRoundPage
                }
                .tabViewStyle(.page)
            } else {
                VStack(spacing: 12) {
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
        .onReceive(locationManager.$lastLocation) { location in
            updateLiveDistance(location: location)
        }
        .onReceive(roundStore.$rounds) { _ in
            updateLiveDistance(location: locationManager.lastLocation)
        }
    }

    private func playPage(_ round: Round) -> some View {
        VStack(spacing: 6) {
            Text("Hole \(round.currentHoleNumber)")
                .font(.caption)
                .fontWeight(.semibold)

            Text("Previous: \(liveDistance ?? previousDistance(round: round))")
                .font(.caption2)
                .fontWeight(.semibold)

            Text("Strokes: \(round.currentHole.strokeCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: markBall) {
                Label("At my ball", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            HStack(spacing: 12) {
                Button {
                    roundStore.previousHole()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("Prev")
                    }
                }
                .disabled(round.currentHoleIndex == 0)

                Spacer()

                Button {
                    roundStore.nextHole()
                } label: {
                    HStack(spacing: 2) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                }
                .disabled(round.holes.count >= 18 && round.currentHoleIndex == round.holes.count - 1)
            }
            .font(.caption2)
        }
        .padding()
    }

    private var endRoundPage: some View {
        VStack {
            Spacer()
            Button("End Round", role: .destructive) {
                locationManager.stopUpdating()
                roundStore.endRound()
            }
            .font(.headline)
            Spacer()
        }
        .padding()
    }

    private func updateLiveDistance(location: CLLocation?) {
        guard let location,
              let lastMark = roundStore.activeRound?.marks.last else {
            liveDistance = nil
            return
        }
        liveDistance = DistanceCalculator.formattedYards(from: location, to: lastMark.location)
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
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            showSwingAway = false
        }
    }
}
