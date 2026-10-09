import MapKit
import SwiftUI

/// A round's holes on the map: the header of holes, the map, the distances over it, and the
/// buttons under it. An active round shows its display hole and follows the player; a past
/// round shows any hole picked in the header.
struct RoundMapView: View {
    let roundID: UUID
    @Environment(PhoneServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.stationaryThreshold) private var stationaryThreshold: TimeInterval = 30

    private var round: Round? {
        services.roundStore.round(roundID)
    }

    @State private var camera = MapCameraState()
    @State private var spot = SpotSelection()
    /// The hole shown in a past round. An active round shows its display hole, which the watch's
    /// GPS and the user move.
    @State private var pastHoleIndex = 0
    @State private var isEditing = false
    /// The whole round's GPS, and the part of it on the hole shown.
    @State private var roundTrack: [TrackPoint] = []
    @State private var holeTrack: [TrackPoint] = []
    /// The hole's track as the map draws it, without the fixes too close together to show.
    @State private var trackLine: [CLLocationCoordinate2D] = []
    @State private var suggestions: [StrokeSuggestion] = []
    @State private var showHoleTimes = false
    @State private var showScorecard = false
    /// The scorecard's edit button picked another hole: edit mode starts once the map shows it.
    @State private var editsAfterHoleChange = false
    /// A point the player tapped on the map, to see how far it is.
    @State private var target: CLLocationCoordinate2D?

    var body: some View {
        Group {
            if let round {
                roundContent(round)
            }
        }
        .onAppear {
            services.locationManager.startUpdating()
            reloadTrack()
            // A past round shows its holes, not the player, so it does not wait for a location
            if let round, !round.isActive, !camera.hasInitialPan {
                camera.hasInitialPan = true
                panToHole()
            }
        }
        .onDisappear {
            services.locationManager.stopUpdating()
        }
        .onChange(of: services.locationManager.lastLocation, initial: true) { _, location in
            if !camera.hasInitialPan, location != nil, round != nil {
                camera.hasInitialPan = true
                panToHole()
            } else if camera.followsUserLocation, round?.isActive == true, let location {
                camera.position = MapGeometry.following(location, heading: shownHoleHeading)
            }
        }
        .onChange(of: services.roundStore.revision) {
            if round == nil {
                dismiss()
            }
            // A new stroke can start its hole in the timeline, which changes the hole's track
            filterTrack()
        }
        .onChange(of: round.map(shownHoleIndex)) {
            // Also covers a hole change from the watch
            isEditing = editsAfterHoleChange
            editsAfterHoleChange = false
            target = nil
            panToHole()
            filterTrack()
        }
        .onChange(of: isEditing) {
            refreshSuggestions()
        }
        .onChange(of: round?.hiddenSuggestionIDs, initial: true) {
            refreshSuggestions()
        }
        .onChange(of: services.streamStore.revision) {
            // Records arrived from the watch
            reloadTrack()
        }
    }

    /// The hole the map, header, and distances describe: an active round's display hole, which
    /// the watch shows too. A past round opens on its first hole.
    private func shownHoleIndex(_ round: Round) -> Int {
        round.isActive ? round.displayHoleIndex : pastHoleIndex
    }

    private var shownHoleHeading: Double? {
        round.flatMap { MapGeometry.heading(of: $0, holeIndex: shownHoleIndex($0)) }
    }

    @ViewBuilder
    private func roundContent(_ round: Round) -> some View {
        let holeIndex = shownHoleIndex(round)
        VStack(spacing: 0) {
            HoleHeaderView(round: round, shownHoleIndex: holeIndex, selectHole: { selectHole($0, round) },
                           openScorecard: { showScorecard = true })
            RoundSyncBanner(round: round)
            ZStack(alignment: .top) {
                RoundMapLayer(round: round, shownHoleIndex: holeIndex, isEditing: isEditing,
                              trackLine: trackLine, holeTrack: holeTrack, suggestions: suggestions,
                              camera: $camera, target: $target, spot: $spot)
                VStack {
                    MapInfoOverlay(round: round, shownHoleIndex: holeIndex, target: $target)
                    Spacer()
                    MapButtonBar(round: round, shownHoleIndex: holeIndex, isEditing: $isEditing,
                                 showHoleTimes: $showHoleTimes, followsUserLocation: camera.followsUserLocation,
                                 followUserLocation: followUserLocation)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showHoleTimes) {
            HoleTimelineView(roundID: round.id)
        }
        .fullScreenCover(isPresented: $showScorecard) {
            ScorecardView(roundID: round.id) { editHole($0, round) }
        }
        // The header has its own back button, so the bar is hidden
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { spot.stroke != nil && !spot.confirmsDelete },
            set: { if !$0 && !spot.confirmsDelete { spot.stroke = nil } }
        )) {
            SpotEditSheet(round: round, shownHoleIndex: holeIndex, spot: $spot)
        }
        .alert("Delete Spot", isPresented: $spot.confirmsDelete) {
            Button("Delete", role: .destructive) {
                if let stroke = spot.stroke {
                    services.roundStore.removeStroke(stroke, from: round.id)
                }
                spot.stroke = nil
            }
            Button("Cancel", role: .cancel) {
                spot.confirmsDelete = false
            }
        } message: {
            Text("Are you sure you want to delete this spot?")
        }
    }

    /// Shows a hole. During a round the watch shows it too, and its GPS moves on from there.
    /// The timeline does not change: a hole starts with its first stroke.
    private func selectHole(_ index: Int, _ round: Round) {
        if index == shownHoleIndex(round) {
            panToHole()
        } else if round.isActive {
            services.roundStore.setDisplayHole(index, roundID: round.id)
        } else {
            pastHoleIndex = index
        }
    }

    /// Shows hole `index` in edit mode, from the scorecard.
    private func editHole(_ index: Int, _ round: Round) {
        showScorecard = false
        if index == shownHoleIndex(round) {
            isEditing = true
        } else {
            editsAfterHoleChange = true
            selectHole(index, round)
        }
    }

    private func followUserLocation() {
        camera.followsUserLocation = true
        if let location = services.locationManager.lastLocation {
            camera.position = MapGeometry.following(location, heading: shownHoleHeading)
        }
    }

    private func panToHole() {
        guard let round, let holeCamera = MapGeometry.holeCamera(round, holeIndex: shownHoleIndex(round)) else { return }
        camera.followsUserLocation = false
        camera.position = .camera(holeCamera)
    }

    // MARK: - Track and suggestions

    /// Loads the watch's GPS track and picks out the hole shown.
    private func reloadTrack() {
        guard let round else {
            roundTrack = []
            holeTrack = []
            trackLine = []
            suggestions = []
            return
        }
        roundTrack = services.streamStore.points(for: round.id, until: round.endedAt)
        filterTrack()
    }

    /// Picks out the track on the hole shown and works out the suggestions again.
    private func filterTrack() {
        guard let round else { return }
        holeTrack = HoleTrack.points(roundTrack, in: round, holeIndex: shownHoleIndex(round))
        trackLine = TrackLine.coordinates(of: holeTrack)
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        guard let round, isEditing else {
            suggestions = []
            return
        }
        suggestions = StrokeFinder.suggestions(
            in: round,
            holeIndex: shownHoleIndex(round),
            points: roundTrack,
            swings: services.streamStore.swings(for: round.id, until: round.endedAt),
            contacts: services.streamStore.contacts(for: round.id, until: round.endedAt),
            minStop: stationaryThreshold,
            hidden: Set(round.hiddenSuggestionIDs)
        )
    }
}
