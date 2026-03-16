import SwiftUI
import CoreLocation
import CourseData

struct WatchRoundView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var syncService: SyncService

    @State private var showSwingAway = false
    @State private var showNoLocation = false

    @State private var liveDistance: String?

    var body: some View {
        Group {
            if showSwingAway {
                swingAwayView(round: roundStore.activeRound)
            } else if let round = roundStore.activeRound {
                TabView {
                    playPage(round)
                    endRoundPage
                }
                .tabViewStyle(.page)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: syncService.isConnected ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                            .font(.system(size: 10))
                            .foregroundStyle(syncService.isConnected ? .green : .secondary)
                        Text("No active round")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

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
        }
        .onReceive(locationManager.$lastLocation) { location in
            updateLiveDistance(location: location)
        }
        .onReceive(roundStore.$rounds) { _ in
            updateLiveDistance(location: locationManager.lastLocation)
        }
        .alert("Waiting for GPS", isPresented: $showNoLocation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Location not available yet. Please wait a moment and try again.")
        }
    }

    private func playPage(_ round: Round) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: syncService.isConnected ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(syncService.isConnected ? .green : .secondary)
                Text("Hole \(round.currentHoleNumber)")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

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

    @ViewBuilder
    private func swingAwayView(round: Round?) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Swing away")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)

                if let round, let courseHole = round.currentCourseHole,
                   let course = round.courseSelection?.course,
                   let green = courseHole.green(from: course.features),
                   let location = locationManager.lastLocation {
                    let direction: Vector2D = courseHole.vector(for: green.id, from: course.features)
                        ?? Vector2D(
                            dx: green.center.latitude - location.coordinate.latitude,
                            dy: green.center.longitude - location.coordinate.longitude
                        ).normalized()
                    let greenDist = DistanceCalculator.greenDistances(from: location, green: green, direction: direction)

                    Divider()

                    HStack(spacing: 12) {
                        VStack(spacing: 1) {
                            Text("\(greenDist.front)")
                                .font(.body).fontWeight(.bold)
                            Text("Front")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 1) {
                            Text("\(greenDist.middle)")
                                .font(.body).fontWeight(.bold)
                            Text("Mid")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 1) {
                            Text("\(greenDist.back)")
                                .font(.body).fontWeight(.bold)
                            Text("Back")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    let holeFeatures = course.features(for: courseHole)
                    let features = DistanceCalculator.featuresAhead(
                        from: location, features: holeFeatures, green: green
                    )
                    if !features.isEmpty {
                        Divider()
                        ForEach(features, id: \.feature.id) { fd in
                            HStack {
                                Image(systemName: fd.feature.type == .water ? "drop.fill" : "square.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(fd.feature.type == .water ? .blue : .yellow)
                                Text(fd.feature.type == .water ? "Water" : "Bunker")
                                    .font(.caption2)
                                Spacer()
                                Text("\(fd.distanceYards)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }

                Spacer()

                Button("Dismiss") {
                    showSwingAway = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private func markBall() {
        guard let location = locationManager.lastLocation else {
            locationManager.requestLocation()
            showNoLocation = true
            return
        }
        let mark = BallMark(coordinate: location.coordinate)
        roundStore.addMark(mark)
        showSwingAway = true
    }
}
