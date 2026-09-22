import SwiftUI
import CoreLocation
import CourseDataSwift

struct WatchRoundView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var guessStore: GuessStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var breadcrumbRecorder: BreadcrumbRecorder
    @EnvironmentObject var swingDetector: SwingDetector

    @State private var liveDistance: String?

    var body: some View {
        Group {
            if let round = roundStore.activeRound {
                TabView {
                    infoPage(round)
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
                        workoutManager.start()
                        startGuessDetection()
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
                workoutManager.start()
                startGuessDetection()
            }
        }
        .onChange(of: roundStore.activeRound != nil) {
            if roundStore.activeRound != nil {
                locationManager.startUpdating()
                workoutManager.start()
                startGuessDetection()
            }
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .onReceive(locationManager.$lastLocation) { location in
            updateLiveDistance(location: location)
            if let round = roundStore.activeRound,
               let selection = round.courseSelection,
               let location,
               let detected = HoleAdvancer.detectHole(location: location, courseSelection: selection, currentHoleIndex: round.currentHoleIndex) {
                roundStore.setHoleIndex(detected)
            }
            if let location, roundStore.activeRound != nil {
                breadcrumbRecorder.updateLocation(location)
                swingDetector.updateLocation(location.coordinate)
                checkForSwingGuess()
            }
        }
        .onReceive(roundStore.$rounds) { _ in
            updateLiveDistance(location: locationManager.lastLocation)
        }
        .onChange(of: breadcrumbRecorder.isStationary) {
            if breadcrumbRecorder.isStationary {
                checkForStationaryGuess()
            }
        }
    }

    // MARK: - Info Page

    private func infoPage(_ round: Round) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                if let courseHole = round.currentCourseHole,
                   let course = round.courseSelection?.course,
                   let green = courseHole.green(from: course.features),
                   let location = locationManager.lastLocation {
                    let direction = courseDirection(hole: courseHole, green: green, location: location, course: course)
                    let greenDist = DistanceCalculator.greenDistances(from: location, green: green, direction: direction)

                    holeTitle("Hole \(courseHole.number) · Par \(courseHole.par)", round)

                    Divider()

                    greenDistancesView(greenDist)

                    let holeFeatures = course.features(for: courseHole)
                    let features = DistanceCalculator.featuresAhead(from: location, features: holeFeatures, green: green, limit: 7)
                    if !features.isEmpty {
                        Divider()
                        featuresView(features)
                    }

                    Divider()

                    holeStatsView(round)
                } else {
                    holeTitle("Hole \(round.currentHoleNumber)", round)

                    Divider()

                    holeStatsView(round)
                }
            }
            .padding()
        }
    }

    /// The hole's name between two small arrows that go to the previous and next hole.
    private func holeTitle(_ title: String, _ round: Round) -> some View {
        HStack(spacing: 4) {
            holeArrow("chevron.left", label: "Previous hole", disabled: round.currentHoleIndex == 0) {
                roundStore.previousHole()
            }

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)

            holeArrow("chevron.right", label: "Next hole",
                      disabled: round.holes.count >= Round.maxHoles && round.currentHoleIndex == round.holes.count - 1) {
                roundStore.nextHole()
            }
        }
    }

    private func holeArrow(_ systemName: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption2)
                .fontWeight(.bold)
                .frame(width: 26, height: 22)
                .background(Capsule().fill(Color.secondary.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    private var endRoundPage: some View {
        VStack {
            Spacer()
            Button("End Round", role: .destructive) {
                locationManager.stopUpdating()
                workoutManager.stop()
                stopGuessDetection()
                roundStore.endRound()
            }
            .font(.headline)
            Spacer()
        }
        .padding()
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func holeStatsView(_ round: Round) -> some View {
        HStack {
            Text("Previous")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(liveDistance ?? previousDistance(round: round))
                .font(.caption2)
                .fontWeight(.semibold)
        }
        HStack {
            Text("Strokes")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(round.currentHole.strokeCount)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
    }

    private func greenDistancesView(_ distances: GreenDistances) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text("\(distances.front)")
                    .font(.body).fontWeight(.bold)
                Text("Front")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 1) {
                Text("\(distances.middle)")
                    .font(.body).fontWeight(.bold)
                Text("Mid")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 1) {
                Text("\(distances.back)")
                    .font(.body).fontWeight(.bold)
                Text("Back")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func featuresView(_ features: [FeatureDistance]) -> some View {
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

    private func courseDirection(hole: Hole, green: Feature, location: CLLocation, course: Course) -> Vector2D {
        hole.vector(for: green.id, from: course.features)
            ?? Vector2D(
                dx: green.center.latitude - location.coordinate.latitude,
                dy: green.center.longitude - location.coordinate.longitude
            ).normalized()
    }

    // MARK: - Helpers

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

    // MARK: - Guess Detection

    private func startGuessDetection() {
        guard settingsStore.settings.missedMarkGuessesEnabled else { return }
        breadcrumbRecorder.updateThreshold(settingsStore.settings.stationaryThreshold)
        breadcrumbRecorder.reset()
        breadcrumbRecorder.start()
        swingDetector.start()
    }

    private func stopGuessDetection() {
        swingDetector.stop()
        breadcrumbRecorder.reset()
    }

    private func checkForSwingGuess() {
        guard settingsStore.settings.missedMarkGuessesEnabled,
              let round = roundStore.activeRound,
              let swing = swingDetector.consumeSwing() else { return }

        let guess = MissedMarkGuess(
            coordinate: swing.coordinate,
            timestamp: swing.timestamp,
            holeIndex: round.currentHoleIndex,
            reason: .swing,
            roundID: round.id
        )
        guessStore.add(guess)
        syncService.send(.addGuess(guess, round.id))
    }

    private func checkForStationaryGuess() {
        guard settingsStore.settings.missedMarkGuessesEnabled,
              let round = roundStore.activeRound,
              let coord = breadcrumbRecorder.consumeStationaryLocation() else { return }

        let guess = MissedMarkGuess(
            coordinate: coord,
            timestamp: Date(),
            holeIndex: round.currentHoleIndex,
            reason: .stationary,
            roundID: round.id
        )
        guessStore.add(guess)
        syncService.send(.addGuess(guess, round.id))
    }
}
