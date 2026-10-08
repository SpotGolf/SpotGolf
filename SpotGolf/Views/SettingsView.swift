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
    @AppStorage(SettingsKey.sharePins) private var sharePins = true

    private let thresholdOptions = stride(from: 10, through: 120, by: 5).map { $0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Stationary Threshold", selection: $stationaryThreshold) {
                        ForEach(thresholdOptions, id: \.self) { seconds in
                            Text("\(seconds)s").tag(TimeInterval(seconds))
                        }
                    }
                } header: {
                    Text("Stroke Suggestions")
                } footer: {
                    Text("How long you must stand still on or near the green, with no swing, before a chip or putt is suggested.")
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
                    NavigationLink("Putt Captures") { PuttCapturesView() }
                } header: {
                    Text("Putt Lab")
                } footer: {
                    Text("Sensor recordings from the watch's Putt Lab page, for working out how to detect putts.")
                }
                #if DEBUG
                ImportRoundSection(showCoursePicker: $showImportCoursePicker, message: importMessage)
                #endif
                Section {
                    LabeledContent("Version", value: AppVersion.text())
                        .accessibilityIdentifier("AppVersion")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
                    Log.export.error("Import failed: \(String(describing: error), privacy: .public)")
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
