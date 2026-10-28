import MapKit
import SwiftUI

/// A round's holes on the map: the header of holes, the map, the distances over it, and the
/// buttons under it. An active round shows its display hole and follows the player; a past
/// round shows any hole picked in the header.
struct RoundMapView: View {
    let roundID: UUID
    @Environment(PhoneServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
    /// Keeps an active round's map on its hole while a spot is edited.
    @State private var hold = HoleHold()
    /// A spot on the map is being dragged.
    @State private var isDraggingSpot = false
    /// The whole round's GPS, and the part of it on the hole shown.
    @State private var roundTrack: [TrackPoint] = []
    @State private var holeTrack: [TrackPoint] = []
    /// The fixes where the hole shown could start, for the time of a spot placed by hand.
    @State private var startWindow: [TrackPoint] = []
    /// The hole's track as the map draws it, without the fixes too close together to show.
    @State private var trackLine: [CLLocationCoordinate2D] = []
    @State private var suggestions: [StrokeSuggestion] = []
    @State private var showScorecard = false
    /// A point the player tapped on the map, to see how far it is.
    @State private var target: CLLocationCoordinate2D?
    /// How the map draws the ground. Read from the settings when the map opens, and kept there
    /// each time the style sheet picks one.
    @State private var mapStyle = MapStyleChoice.standard
    @State private var showMapStyles = false
    @State private var greenView = GreenViewState()
    /// The lines and distances between the shown hole's strokes, which the ruler button turns on and off.
    @State private var showsStrokeLines = false

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
        }
        .onChange(of: services.roundStore.revision) {
            if round == nil {
                dismiss()
            }
            // A stroke change can move its hole's start, which changes the hole's track
            filterTrack()
        }
        .onChange(of: isEditing) { _, editing in
            guard let round else { return }
            hold.editChanged(isEditing: editing, shownHoleIndex: shownHoleIndex(round))
        }
        .onChange(of: isEditingSpot) {
            // Starting and ending a spot edit each give the player time before the watch moves on
            if let round, round.isActive {
                services.roundStore.holdDisplayHole(roundID: round.id)
            }
        }
        .onChange(of: round.map(shownHoleIndex)) {
            target = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                greenView.holeChanged()
            }
            panToHole()
            filterTrack()
        }
        .onChange(of: services.streamStore.revision) {
            // Records arrived from the watch
            reloadTrack()
        }
        .onChange(of: scenePhase) { _, phase in
            // Stream records and round changes that arrived in the background
            if phase == .active {
                reloadTrack()
            }
        }
    }

    /// The hole the map, header, and distances describe: an active round's display hole, which
    /// the watch shows too, or the hole `hold` keeps. A past round opens on its first hole.
    private func shownHoleIndex(_ round: Round) -> Int {
        guard round.isActive else { return pastHoleIndex }
        return hold.holeIndex(lastHoleIndex: round.lastHoleIndex) ?? round.displayHoleIndex
    }

    /// A spot's sheet is open, a spot is being dragged, or Green View is open.
    private var isEditing: Bool {
        isEditingSpot || greenView.isShown
    }

    /// A spot's sheet is open or a spot is being dragged. Taking a suggestion opens its sheet.
    private var isEditingSpot: Bool {
        spot.stroke != nil || isDraggingSpot
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
                RoundMapLayer(round: round, shownHoleIndex: holeIndex, showsStrokeLines: showsStrokeLines,
                              isDraggingSpot: $isDraggingSpot, trackLine: trackLine, holeTrack: holeTrack, startWindow: startWindow,
                              suggestions: suggestions, mapStyle: mapStyle, camera: $camera, target: $target, spot: $spot)
                if greenView.isShown {
                    // Over the map rather than in place of it, so the map keeps its camera
                    GreenView(round: round, shownHoleIndex: holeIndex,
                              trackLine: trackLine, holeTrack: holeTrack, startWindow: startWindow,
                              suggestions: suggestions, spot: $spot) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            greenView.close()
                        }
                    }
                    .transition(.opacity)
                }
                VStack {
                    if !greenView.isShown {
                        MapInfoOverlay(round: round, shownHoleIndex: holeIndex, target: $target)
                    }
                    Spacer()
                    MapButtonBar(round: round, shownHoleIndex: holeIndex, showsStrokeLines: $showsStrokeLines,
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
        .sheet(isPresented: $showMapStyles) {
            MapStyleSheet(selected: mapStyle, center: previewCenter(round, holeIndex: holeIndex), select: selectMapStyle)
        }
        .fullScreenCover(isPresented: $showScorecard) {
            ScorecardView(roundID: round.id) { showHoleFromScorecard($0, round) }
        }
        // The header has its own back button, so the bar is hidden
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { spot.stroke != nil && !spot.confirmsDelete },
            // Swiping the sheet away is Cancel
            set: { if !$0 && !spot.confirmsDelete {
                SpotActions.cancel(round: round, startWindow: startWindow, services: services, spot: &spot)
            } }
        )) {
            SpotEditSheet(round: round, shownHoleIndex: holeIndex, startWindow: startWindow, spot: $spot)
        }
        .alert("Delete Spot", isPresented: $spot.confirmsDelete) {
            Button("Delete", role: .destructive) {
                if let stroke = spot.stroke {
                    SpotActions.remove(stroke, round: round, startWindow: startWindow, services: services)
                }
                spot.close()
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
        hold.release()
        if round.isActive {
            services.roundStore.setDisplayHole(index, roundID: round.id, holds: true)
        } else {
            pastHoleIndex = index
        }
    }

    /// Shows hole `index`, picked on the scorecard.
    private func showHoleFromScorecard(_ index: Int, _ round: Round) {
        showScorecard = false
        selectHole(index, round)
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

    /// Loads the watch's GPS track and picks out the hole shown. Waits while the app is not
    /// active: returning to it loads everything that changed.
    private func reloadTrack() {
        guard scenePhase == .active else { return }
        guard let round else {
            roundTrack = []
            holeTrack = []
            startWindow = []
            trackLine = []
            suggestions = []
            return
        }
        roundTrack = services.streamStore.points(for: round.id, until: round.endedAt)
        filterTrack()
    }

    /// Picks out the track on the hole shown and works out the suggestions again. Waits while
    /// the app is not active, as `reloadTrack` does.
    private func filterTrack() {
        guard scenePhase == .active, let round else { return }
        holeTrack = HoleTrack.points(roundTrack, in: round, holeIndex: shownHoleIndex(round))
        startWindow = HoleTrack.startWindow(roundTrack, in: round, holeIndex: shownHoleIndex(round))
        trackLine = TrackLine.coordinates(of: holeTrack)
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        guard let round else {
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
            hidden: round.takenSuggestionIDs
        )
    }
}
