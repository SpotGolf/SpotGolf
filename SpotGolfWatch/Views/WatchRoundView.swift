import SwiftUI

struct WatchRoundView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var showConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            if let round = roundStore.activeRound {
                // Distance from last shot
                if round.marks.count >= 2 {
                    let last = round.marks[round.marks.count - 1]
                    let prev = round.marks[round.marks.count - 2]
                    Text(DistanceCalculator.formattedYards(from: prev, to: last))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("last shot")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("\(round.marks.count) mark\(round.marks.count == 1 ? "" : "s")")
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
        .overlay {
            if showConfirmation {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showConfirmation)
    }

    private func markBall() {
        locationManager.requestLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let location = locationManager.lastLocation else { return }
            let mark = BallMark(coordinate: location.coordinate)
            roundStore.addMark(mark)

            showConfirmation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showConfirmation = false
            }
        }
    }
}
