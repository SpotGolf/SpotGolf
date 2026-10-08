import SwiftUI
import WatchKit
import CoreLocation
import CourseDataSwift

struct WatchRoundView: View {
    @Environment(WatchServices.self) private var services

    @State private var liveDistance: String?

    var body: some View {
        Group {
            if let round = services.roundStore.activeRound {
                TabView {
                    infoPage(round)
                    endRoundPage
                }
                .tabViewStyle(.page)
            } else {
                TabView {
                    noRoundPage
                    PuttLabView()
                }
                .tabViewStyle(.page)
            }
        }
        .onChange(of: services.locationManager.lastLocation, initial: true) { _, location in
            updateLiveDistance(location: location)
        }
        .onChange(of: services.roundStore.revision) {
            updateLiveDistance(location: services.locationManager.lastLocation)
        }
    }

    /// Lets UI tests see whether the workout was recovered after a relaunch, and when it was
    /// saved after the round ended. Only rendered under --ui-testing; must be normal-sized or
    /// the accessibility tree drops it and queries can't find it.
    @ViewBuilder
    private var workoutStatus: some View {
        if services.showsWorkoutStatus {
            Text(verbatim: services.workoutManager.status.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("workoutStatus")
        }
    }

    private var noRoundPage: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: services.syncService.isConnected ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(services.syncService.isConnected ? .green : .secondary)
                Text("No active round")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // A round needs a course, and courses are picked on the phone
            Text("Start a round on your iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            workoutStatus
        }
        .padding()
    }

    // MARK: - Info Page

    private func infoPage(_ round: Round) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                let course = round.courseSelection.course
                if let courseHole = round.displayCourseHole,
                   let green = courseHole.green(from: course.features),
                   let location = services.locationManager.lastLocation {
                    let direction = courseDirection(hole: courseHole, green: green, location: location, course: course)
                    // Mid is to the pin once it is known; the center pin is the green's center
                    let pin = round.targetCoordinate(holeIndex: round.displayHoleIndex)
                        .map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
                    let greenDist = DistanceCalculator.greenDistances(from: location, green: green, direction: direction, middle: pin)

                    holeTitle("Hole \(courseHole.number) · Par \(courseHole.par)", round)

                    if round.isOnGreen(location.coordinate, holeIndex: round.displayHoleIndex) {
                        setPinButton(location, round)
                    }

                    Divider()

                    greenDistancesView(greenDist, toPin: round.hasKnownPin(holeIndex: round.displayHoleIndex))

                    let holeFeatures = course.features(for: courseHole)
                    let features = DistanceCalculator.featuresAhead(from: location, features: holeFeatures, green: green, limit: 7)
                    if !features.isEmpty {
                        Divider()
                        featuresView(features)
                    }

                    Divider()

                    holeStatsView(round)
                } else {
                    holeTitle("Hole \(round.displayHoleNumber)", round)

                    Divider()

                    holeStatsView(round)
                }

                workoutStatus
            }
            .padding()
        }
    }

    /// The hole's name between two small arrows that show the previous and next hole. They
    /// change the display hole, which the phone shows too; the timeline is set by strokes.
    private func holeTitle(_ title: LocalizedStringKey, _ round: Round) -> some View {
        let shown = round.displayHoleIndex
        return HStack(spacing: 4) {
            holeArrow("chevron.left", label: "Previous hole", disabled: shown == 0) {
                services.contactMonitor.tapped()
                services.roundStore.setDisplayHole(shown - 1)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)

            holeArrow("chevron.right", label: "Next hole", disabled: shown >= round.lastHoleIndex) {
                services.contactMonitor.tapped()
                services.roundStore.setDisplayHole(shown + 1)
            }
        }
    }

    private func holeArrow(_ systemName: String, label: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
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

    /// Shown only on the green: saves where the player stands as the shown hole's pin.
    private func setPinButton(_ location: CLLocation, _ round: Round) -> some View {
        Button {
            services.roundStore.setPin(location.coordinate, holeIndex: round.displayHoleIndex)
            WKInterfaceDevice.current().play(.success)
        } label: {
            Label("Set pin location", systemImage: "flag.fill")
                .font(.caption2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .tint(.red)
        .accessibilityIdentifier("setPinLocation")
    }

    private var endRoundPage: some View {
        VStack {
            Spacer()
            Button("End Round", role: .destructive) {
                services.watchSync.endRound()
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
            Text(liveDistance ?? previousDistance(strokes: round.displayHoleStrokes))
                .font(.caption2)
                .fontWeight(.semibold)
        }
        HStack {
            Text("Strokes")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(round.displayHoleStrokes.count)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
    }

    /// Front, middle and back. The middle is labeled Pin once the pin is known.
    private func greenDistancesView(_ distances: GreenDistances, toPin: Bool) -> some View {
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
                Text(toPin ? "Pin" : "Mid")
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
              let lastStroke = services.roundStore.activeRound?.displayHoleStrokes.last else {
            liveDistance = nil
            return
        }
        liveDistance = DistanceCalculator.formattedYards(from: location, to: lastStroke.location)
    }

    private func previousDistance(strokes: [Stroke]) -> String {
        if strokes.count >= 2 {
            return DistanceCalculator.formattedYards(from: strokes[strokes.count - 2], to: strokes[strokes.count - 1])
        }
        return String(localized: "\(0) yds")
    }
}
