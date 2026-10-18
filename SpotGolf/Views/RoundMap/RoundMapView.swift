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
    @AppStorage(SettingsKey.greenZone) private var greenZone: Double = HoleShape.chipZoneMargin

    private var round: Round? {
        services.roundStore.round(roundID)
    }

    @State private var camera = MapCameraState()
    @State private var spot = SpotSelection()
    /// The hole shown in a past round. An active round shows its display hole, which the watch's
    /// GPS and the user move.
    @State private var pastHoleIndex = 0
    @State private var isEditing = false
    /// The hole held on screen while editing. The watch's GPS can move the display hole on when
    /// the player reaches the next tee, but an edit in progress stays on its hole until Done.
    @State private var editingHoleIndex: Int?
    /// The whole round's GPS, and the part of it on the hole shown.
    @State private var roundTrack: [TrackPoint] = []
    @State private var holeTrack: [TrackPoint] = []
    /// The hole's track as the map draws it, without the fixes too close together to show.
    @State private var trackLine: [CLLocationCoordinate2D] = []
    @State private var suggestions: [StrokeSuggestion] = []
    @State private var showHoleTimes = false
    @State private var showLog = false
    @State private var showScorecard = false
    /// The scorecard's edit button picked another hole: edit mode starts once the map shows it.
    @State private var editsAfterHoleChange = false
    /// A point the player tapped on the map, to see how far it is.
    @State private var target: CLLocationCoordinate2D?
    /// How the map draws the ground. Read from the settings when the map opens, and kept there
    /// each time the style sheet picks one.
    @State private var mapStyle = MapStyleChoice.standard
    @State private var showMapStyles = false
    @State private var greenView = GreenViewState()

    var body: some View {
        Group {
            if let round {
                roundContent(round)
            }
        }
        .onAppear {
            mapStyle = MapStyleChoice.stored()
            services.locationManager.startUpdating()
            reloadTrack()
            // Settings changed since the round started reach the watch now
            if round?.isActive == true {
                services.phoneSync.sendSettings()
            }
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
                camera.follow(location, heading: shownHoleHeading)
            }
            if let round, round.isActive, let location {
                withAnimation(.easeInOut(duration: 0.2)) {
                    greenView.playerMoved(metersOffGreen: round.metersOffGreen(location.coordinate,
                                                                              holeIndex: shownHoleIndex(round)))
                }
            }
        }
        .onChange(of: services.roundStore.revision) {
            if round == nil {
                dismiss()
            }
            // A new stroke can start its hole in the timeline, which changes the hole's track
            filterTrack()
        }
        .onChange(of: round.map(shownHoleIndex)) { _, shown in
            // A hole the user picked, or the display hole catching up after Done. The watch's
            // hole changes are held off while editing, so they do not land here until then.
            isEditing = editsAfterHoleChange
            editsAfterHoleChange = false
            editingHoleIndex = isEditing ? shown : nil
            target = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                greenView.holeChanged()
            }
            panToHole()
            filterTrack()
        }
        .onChange(of: greenView.isShown) { _, shown in
            // Green View is for marking putts, so it is always in edit mode. Its X ends editing; a
            // hole change sets editing itself.
            if shown {
                isEditing = true
            }
        }
        .onChange(of: isEditing) {
            editingHoleIndex = isEditing ? round.map(shownHoleIndex) : nil
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
    /// the watch shows too, or the hole being edited while an edit holds it. A past round opens
    /// on its first hole.
    private func shownHoleIndex(_ round: Round) -> Int {
        if let editingHoleIndex, editingHoleIndex <= round.lastHoleIndex {
            return editingHoleIndex
        }
        return round.isActive ? round.displayHoleIndex : pastHoleIndex
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
                              mapStyle: mapStyle, camera: $camera, target: $target, spot: $spot)
                if greenView.isShown {
                    // Over the map rather than in place of it, so the map keeps its camera
                    GreenView(round: round, shownHoleIndex: holeIndex,
                              trackLine: trackLine, holeTrack: holeTrack, suggestions: suggestions,
                              spot: $spot) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            greenView.close()
                        }
                        isEditing = false
                    }
                    .transition(.opacity)
                }
                VStack {
                    if !greenView.isShown {
                        MapInfoOverlay(round: round, shownHoleIndex: holeIndex, target: $target)
                    }
                    Spacer()
                    MapButtonBar(round: round, shownHoleIndex: holeIndex, isEditing: $isEditing,
                                 showHoleTimes: $showHoleTimes, showLog: $showLog,
                                 followsUserLocation: camera.followsUserLocation,
                                 followUserLocation: followUserLocation,
                                 mapStyle: mapStyle, pickMapStyle: { showMapStyles = true },
                                 showsGreenView: greenView.isShown,
                                 openGreenView: round.green(holeIndex: holeIndex) == nil ? nil : {
                                     withAnimation(.easeInOut(duration: 0.2)) {
                                         greenView.open()
                                     }
                                 })
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showHoleTimes) {
            HoleTimelineView(roundID: round.id)
        }
        .sheet(isPresented: $showLog) {
            LogSheet(scope: .round(round))
        }
        .sheet(isPresented: $showMapStyles) {
            MapStyleSheet(selected: mapStyle, center: previewCenter(round, holeIndex: holeIndex), select: selectMapStyle)
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
            return
        }
        // The user's own choice of hole ends any hold
        editingHoleIndex = nil
        if round.isActive {
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

    /// The style sheet's pick, kept in the settings for the next time the map opens.
    private func selectMapStyle(_ choice: MapStyleChoice) {
        mapStyle = choice
        choice.store()
    }

    /// Where the style sheet's previews look: the shown hole's green, else the player.
    private func previewCenter(_ round: Round, holeIndex: Int) -> CLLocationCoordinate2D {
        round.greenCenter(holeIndex: holeIndex)
            ?? services.locationManager.lastLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    private func followUserLocation() {
        if let location = services.locationManager.lastLocation {
            camera.follow(location, heading: shownHoleHeading)
        } else {
            camera.followsUserLocation = true
        }
    }

    private func panToHole() {
        guard let round, let holeCamera = MapGeometry.holeCamera(round, holeIndex: shownHoleIndex(round)) else { return }
        camera.show(holeCamera)
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
            events: services.streamStore.events(for: round.id, until: round.endedAt),
            minStop: stationaryThreshold,
            zoneMargin: greenZone,
            hidden: Set(round.hiddenSuggestionIDs)
        )
    }
}
