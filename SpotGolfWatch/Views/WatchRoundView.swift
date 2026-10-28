import SwiftUI
import WatchKit
import CoreLocation
import CourseDataSwift

struct WatchRoundView: View {
    /// The round's pages, in order.
    enum Page: Hashable {
        case info
        case end
        case developerMode
    }

    /// The pages with no round, in order.
    enum NoRoundPage: Hashable {
        case home
        case drills
        /// Skip drill and Stop, while a session records.
        case drillControls
    }

    @Environment(WatchServices.self) private var services

    @State private var liveDistance: String?
    @State private var page = Page.info
    @State private var noRoundPage = NoRoundPage.home

    var body: some View {
        Group {
            if let round = services.roundStore.activeRound {
                TabView(selection: $page) {
                    infoPage(round)
                        .tag(Page.info)
                    endRoundPage
                        .tag(Page.end)
                    if services.developerModeInRound {
                        DeveloperModeView()
                            .tag(Page.developerMode)
                    }
                }
                .tabViewStyle(.page)
                .onChange(of: services.developerModeInRound) { _, isOn in
                    if !isOn, page == .developerMode { page = .info }
                }
            } else {
                TabView(selection: $noRoundPage) {
                    noRoundHome
                        .tag(NoRoundPage.home)
                    PuttingDrillsView()
                        .tag(NoRoundPage.drills)
                    if services.drills.state == .recording {
                        DrillControlsView()
                            .tag(NoRoundPage.drillControls)
                    }
                }
                .tabViewStyle(.page)
                // Stop removes the controls page; the drills page shows the session being sent
                .onChange(of: services.drills.state) { was, now in
                    if was == .recording, now != .recording { noRoundPage = .drills }
                }
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

    private var noRoundHome: some View {
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
                        .map { Coordinate(lat: $0.latitude, lon: $0.longitude) }
                    let greenDist = DistanceCalculator.greenDistances(from: location, green: green, direction: direction, middle: pin)

                    // Numbered through the round, as the phone does: the first hole of a second
                    // nine is hole 10, not the nine's own hole 1
                    holeTitle("Hole \(round.displayHoleNumber) · Par \(courseHole.par)", round)

                    if round.isOnGreen(location.coordinate, holeIndex: round.displayHoleIndex) {
                        setPinButton(location, round)
                    }

                    Divider()

                    greenDistancesView(greenDist, toPin: round.hasKnownPin(holeIndex: round.displayHoleIndex))

                    Divider()

                    previousView(round)

                    let holeFeatures = course.features(for: courseHole)
                    let features = DistanceCalculator.featuresAhead(from: location, features: holeFeatures, green: green, limit: 7)
                    if !features.isEmpty {
                        Divider()
                        featuresView(features)
                    }

                    Divider()

                    strokesView(round)
                } else {
                    holeTitle("Hole \(round.displayHoleNumber)", round)

                    Divider()

                    previousView(round)
                    strokesView(round)
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
                services.sensors.tapped()
                services.roundStore.setDisplayHole(shown - 1, holds: true)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)

            holeArrow("chevron.right", label: "Next hole", disabled: shown >= round.lastHoleIndex) {
                services.sensors.tapped()
                services.roundStore.setDisplayHole(shown + 1, holds: true)
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

    /// Shown only on the green: saves where the player stands as the shown hole's pin. Red until
    /// the player has set the pin, then blue and offering to update it.
    private func setPinButton(_ location: CLLocation, _ round: Round) -> some View {
        let isSet = round.hasSetPin(holeIndex: round.displayHoleIndex)
        return Button {
            services.roundStore.setPin(location.coordinate, holeIndex: round.displayHoleIndex)
            services.sensors.play(.success)
        } label: {
            Label(isSet ? "Update pin" : "Set pin location", systemImage: "flag.fill")
                .font(.caption2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .tint(isSet ? .blue : .red)
        .accessibilityIdentifier("setPinLocation")
    }

    private var endRoundPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                highGView

                Button {
                    services.sensors.play(.click)
                    services.hardRestartSensors()
                } label: {
                    Label("Restart Sensors", systemImage: "arrow.clockwise")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("restartSensors")

                Button("End Round", role: .destructive) {
                    services.watchSync.endRound()
                }
                .font(.headline)
            }
            .padding()
        }
    }

    /// The last accelerometer reading over 10 g, as the local time of day and its force. A
    /// swing is well over 10 g, so a stale time on the course means the accelerometer is dead.
    @ViewBuilder
    private var highGView: some View {
        let reading = services.sensors.lastHighG
        HStack {
            Text("Over \(Int(SensorInputs.highGThreshold)) g at")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let reading {
                Text(reading.date, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .fontWeight(.semibold)
            } else {
                Text("None")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityIdentifier("highGTime")
        HStack {
            Text("Force")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let reading {
                Text("\(reading.magnitude, format: .number.precision(.fractionLength(1))) g")
                    .font(.caption2)
                    .fontWeight(.semibold)
            } else {
                Text(verbatim: "—")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityIdentifier("highGForce")
    }

    // MARK: - Shared Components

    private func previousView(_ round: Round) -> some View {
        HStack {
            Text("Previous")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(liveDistance ?? previousDistance(strokes: round.displayHoleStrokes))
                .font(.caption2)
                .fontWeight(.semibold)
        }
    }

    private func strokesView(_ round: Round) -> some View {
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
                dx: green.center.lat - location.coordinate.latitude,
                dy: green.center.lon - location.coordinate.longitude
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
