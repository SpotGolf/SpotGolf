import SwiftUI
import CoreLocation
import CourseDataSwift

struct WatchRoundView: View {
    @EnvironmentObject var roundStore: RoundStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var watchSync: WatchSync
    @EnvironmentObject var workoutManager: WorkoutManager

    @State private var liveDistance: String?
    @EnvironmentObject var holeAdvance: WatchHoleAdvance
    /// A hole the user picked to look at. Nil while the view follows the round's current hole.
    @State private var viewingHoleIndex: Int?

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

                    // A round needs a course, and courses are picked on the phone
                    Text("Start a round on your iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    workoutStatus
                }
                .padding()
            }
        }
        .onReceive(locationManager.$lastLocation) { location in
            updateLiveDistance(location: location)
        }
        .onReceive(roundStore.$rounds) { _ in
            updateLiveDistance(location: locationManager.lastLocation)
        }
        .onChange(of: roundStore.activeRound?.id) {
            resumeRound()
        }
    }

    /// Lets UI tests see whether the workout was recovered after a relaunch, and when it was
    /// saved after the round ended. Only rendered under --ui-testing; must be normal-sized or
    /// the accessibility tree drops it and queries can't find it.
    @ViewBuilder
    private var workoutStatus: some View {
        if CommandLine.arguments.contains("--ui-testing") {
            Text(workoutManager.status.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("workoutStatus")
        }
    }

    /// The hole the page describes.
    private func shownHoleIndex(_ round: Round) -> Int {
        viewingHoleIndex ?? round.currentHoleIndex
    }

    // MARK: - Info Page

    private func infoPage(_ round: Round) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                let course = round.courseSelection.course
                if let courseHole = round.courseHole(at: shownHoleIndex(round)),
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
                    holeTitle("Hole \(shownHoleIndex(round) + 1)", round)

                    Divider()

                    holeStatsView(round)
                }

                if viewingHoleIndex != nil {
                    viewingButtons(round)
                }

                workoutStatus
            }
            .padding()
        }
    }

    /// The hole's name between two small arrows that show the previous and next hole.
    /// They only change the hole shown; the round's current hole stays until "Play this hole".
    private func holeTitle(_ title: String, _ round: Round) -> some View {
        let shown = shownHoleIndex(round)
        return HStack(spacing: 4) {
            holeArrow("chevron.left", label: "Previous hole", disabled: shown == 0) {
                showHole(shown - 1, round)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)

            holeArrow("chevron.right", label: "Next hole", disabled: shown >= round.lastHoleIndex) {
                showHole(shown + 1, round)
            }
        }
    }

    /// "Resume round", and "Play this hole" for a hole after the current one.
    private func viewingButtons(_ round: Round) -> some View {
        VStack(spacing: 4) {
            Button("Resume round") {
                resumeRound()
            }
            if let viewingHoleIndex, viewingHoleIndex > round.currentHoleIndex {
                Button("Play this hole") {
                    roundStore.startHole(viewingHoleIndex, source: .playHole)
                    resumeRound()
                }
            }
        }
        .font(.caption)
    }

    /// Shows a hole without changing the round's current hole, and pauses automatic
    /// hole changes so the page does not jump away while the user looks at it.
    private func showHole(_ index: Int, _ round: Round) {
        if index == round.currentHoleIndex {
            resumeRound()
        } else {
            holeAdvance.pause()
            viewingHoleIndex = index
        }
    }

    /// Goes back to the round's current hole and resumes automatic hole changes.
    private func resumeRound() {
        viewingHoleIndex = nil
        holeAdvance.resume()
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
                watchSync.endRound()
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
            Text(viewingHoleIndex == nil ? liveDistance ?? previousDistance(strokes: round.strokes)
                                         : previousDistance(strokes: round.hole(at: shownHoleIndex(round)).strokes))
                .font(.caption2)
                .fontWeight(.semibold)
        }
        HStack {
            Text("Strokes")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(round.hole(at: shownHoleIndex(round)).strokeCount)")
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
              let lastStroke = roundStore.activeRound?.strokes.last else {
            liveDistance = nil
            return
        }
        liveDistance = DistanceCalculator.formattedYards(from: location, to: lastStroke.location)
    }

    private func previousDistance(strokes: [Stroke]) -> String {
        if strokes.count >= 2 {
            return DistanceCalculator.formattedYards(from: strokes[strokes.count - 2], to: strokes[strokes.count - 1])
        }
        return "0 yds"
    }
}
