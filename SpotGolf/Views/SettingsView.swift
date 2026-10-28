import SwiftUI
import os
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(PhoneServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    #if DEBUG
    @State private var showImportCoursePicker = false
    @State private var importMessage: String?
    #endif

    @AppStorage(SettingsKey.stationaryThreshold) private var stationaryThreshold: TimeInterval = 30
    @AppStorage(SettingsKey.greenZone) private var greenZone: Double = HoleShape.chipZoneMargin
    @AppStorage(SettingsKey.sharePins) private var sharePins = true
    @AppStorage(SettingsKey.debugLogging) private var debugLogging = false
    @AppStorage(SettingsKey.developerMode) private var developerMode = false
    @AppStorage(SettingsKey.iCloudSync) private var iCloudSync = true

    /// Taps on Version toward unlocking Developer Mode, and when the last one was.
    @State private var versionTaps = 0
    @State private var lastVersionTap = Date.distantPast
    @State private var showsDeveloperModeOn = false

    /// Taps on Version that turn Developer Mode on.
    static let developerModeTaps = 7
    /// A pause longer than this between taps starts the count again.
    static let developerModeTapGap: TimeInterval = 2

    private let thresholdOptions = stride(from: 10, through: 120, by: 5).map { $0 }
    private let zoneOptions = stride(from: 5, through: 50, by: 5).map { $0 }

    private var iCloudFooter: String {
        let footer = String(localized: "Saves your rounds, clubs and settings to your iCloud account, and keeps them the same on every iPhone signed in to it. Turning it off keeps them on this iPhone only; what is already in iCloud stays there.")
        // No iCloud account on the phone
        guard iCloudSync, FileManager.default.ubiquityIdentityToken == nil else { return footer }
        return footer + " " + String(localized: "Sign in to iCloud in the Settings app to use it.")
    }

    var body: some View {
        NavigationStack {
            Form {
                UpdateNoticeSection()
                Section {
                    Picker("Stationary Threshold", selection: $stationaryThreshold) {
                        ForEach(thresholdOptions, id: \.self) { seconds in
                            Text("\(seconds)s").tag(TimeInterval(seconds))
                        }
                    }
                    Picker("Green Zone", selection: $greenZone) {
                        ForEach(zoneOptions, id: \.self) { meters in
                            Text("\(meters) m").tag(Double(meters))
                        }
                    }
                    .accessibilityIdentifier("GreenZone")
                } header: {
                    Text("Stroke Suggestions")
                } footer: {
                    Text("How long you must stand still on or near the green, with no swing, before a chip or putt is suggested, and how far from the green's edge still counts as on it. The watch listens for putts in the same zone; a change reaches it when you open the round.")
                }
                Section {
                    NavigationLink {
                        GolfBagView()
                    } label: {
                        LabeledContent("Golf Bag", value: "\(services.golfBag.bag.clubs.count) clubs")
                    }
                    .accessibilityIdentifier("OpenGolfBag")
                } header: {
                    Text("Clubs")
                } footer: {
                    Text("The clubs you carry, up to \(GolfBag.capacity).")
                }
                Section {
                    Toggle("Share Pin Locations", isOn: $sharePins)
                        .accessibilityIdentifier("SharePinLocations")
                } header: {
                    Text("Pins")
                } footer: {
                    Text("Pins you set are shared with other SpotGolf golfers on the same course that day, and you see theirs. Needs an iCloud account. A change takes effect when the next round starts.")
                }
                Section {
                    Toggle("iCloud Sync", isOn: $iCloudSync)
                        .accessibilityIdentifier("iCloudSync")
                } header: {
                    Text("iCloud")
                } footer: {
                    Text(iCloudFooter)
                }
                Section {
                    NavigationLink("Log") { LogView(scope: .outsideRounds) }
                        .accessibilityIdentifier("OpenLog")
                    Toggle("Debug Logging", isOn: $debugLogging)
                        .accessibilityIdentifier("DebugLogging")
                } header: {
                    Text("Log")
                } footer: {
                    Text("What the phone and watch apps recorded outside a round. Each past round has its own log. Debug Logging keeps extra detail on both devices; a change reaches the watch when you open the round.")
                }
                #if DEBUG
                ImportRoundSection(showCoursePicker: $showImportCoursePicker, message: importMessage)
                #endif
                Section {
                    LabeledContent("Version", value: AppVersion.text())
                        .contentShape(Rectangle())
                        .onTapGesture(perform: versionTapped)
                        .accessibilityIdentifier("AppVersion")
                } header: {
                    Text("About")
                }
                if developerMode {
                    Section {
                        Toggle("Developer Mode", isOn: $developerMode)
                            .accessibilityIdentifier("DeveloperMode")
                    } header: {
                        Text("Developer")
                    } footer: {
                        Text("The watch records wrist motion and sound on each green, for working out how to detect putts. The recordings stay on the watch. Get them with Scripts/export-round.py. A change reaches the watch when you open the round.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: debugLogging) { _, enabled in
                Log.isDebugEnabled = enabled
            }
            .onChange(of: iCloudSync) { _, enabled in
                services.setCloudSync(enabled)
            }
            .alert("Developer Mode On", isPresented: $showsDeveloperModeOn) {
                Button("OK") {}
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if DEBUG
        .modifier(ImportRoundPickers(showCoursePicker: $showImportCoursePicker, message: $importMessage))
        #endif
    }

    /// Counts taps on Version; the seventh in a row turns Developer Mode on.
    private func versionTapped() {
        let now = Date()
        versionTaps = now.timeIntervalSince(lastVersionTap) > Self.developerModeTapGap ? 1 : versionTaps + 1
        lastVersionTap = now
        guard !developerMode, versionTaps >= Self.developerModeTaps else { return }
        versionTaps = 0
        developerMode = true
        showsDeveloperModeOn = true
        Log.developerMode.notice("Developer Mode turned on")
    }
}

#if DEBUG
/// Debug builds only: adds a round from a CSV export, to test the stroke suggestions without a watch.
private struct ImportRoundSection: View {
    @Binding var showCoursePicker: Bool
    let message: String?

    @Environment(PhoneServices.self) private var services

    var body: some View {
        Section {
            Button("Import Round…") { showCoursePicker = true }
                .disabled(services.roundStore.currentRound != nil)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Adds a round from a CSV export as the current round and works out its hole starts. Pick the course the round was played on, then the file. Only works when no round is in progress.")
        }
    }
}

/// The course and file pickers for `ImportRoundSection`. The course is picked first, and the
/// file picker opens once the course picker has closed: showing a sheet as the file picker
/// closes makes the new sheet close too.
private struct ImportRoundPickers: ViewModifier {
    @Binding var showCoursePicker: Bool
    @Binding var message: String?

    @Environment(PhoneServices.self) private var services
    @State private var courseSelection: CourseSelection?
    @State private var showFilePicker = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showCoursePicker, onDismiss: {
                showFilePicker = courseSelection != nil
            }) {
                CourseSelectionView(onCourseSelected: { courseSelection = $0 })
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                guard let courseSelection else { return }
                self.courseSelection = nil
                do {
                    let url = try result.get()
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let export = try TrackImporter.read(String(contentsOf: url, encoding: .utf8))
                    let (round, records) = try TrackImporter.round(from: export, courseSelection: courseSelection)
                    guard services.phoneSync.importRound(round, records: records) else {
                        Log.export.error("Import failed: another round is in progress")
                        message = String(localized: "Import failed: another round is in progress.")
                        return
                    }
                    message = String(localized: "Imported \(round.displayTitle): \(export.points.count) fixes, \(export.swings.count) swings, \(export.strokes.count) strokes.")
                } catch {
                    Log.export.error("Import failed: \(String(describing: error))")
                    message = String(localized: "Import failed: \(error.localizedDescription)")
                }
            }
            .onChange(of: showCoursePicker) { _, showing in
                // A course left from a cancelled file picker is not used for the next import
                if showing { courseSelection = nil }
            }
    }
}
#endif
