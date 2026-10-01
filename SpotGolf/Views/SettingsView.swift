import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    #if DEBUG
    @State private var showImportCoursePicker = false
    @State private var importMessage: String?
    #endif

    private let thresholdOptions = stride(from: 10, through: 120, by: 5).map { $0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Stationary Threshold", selection: $settingsStore.settings.stationaryThreshold) {
                        ForEach(thresholdOptions, id: \.self) { seconds in
                            Text("\(seconds)s").tag(TimeInterval(seconds))
                        }
                    }
                } header: {
                    Text("Stroke Suggestions")
                } footer: {
                    Text("How long you must stand still on or near the green, with no swing, before a chip or putt is suggested.")
                }
                #if DEBUG
                ImportRoundSection(showCoursePicker: $showImportCoursePicker, message: importMessage)
                #endif
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

    @EnvironmentObject var roundStore: RoundStore

    var body: some View {
        Section {
            Button("Import Round…") { showCoursePicker = true }
                .disabled(roundStore.currentRound != nil)
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

    @EnvironmentObject var phoneSync: PhoneSync
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
                    guard phoneSync.importRound(round, records: records) else {
                        message = "Import failed: another round is in progress."
                        return
                    }
                    message = "Imported \(round.displayTitle): \(export.points.count) fixes, \(export.swings.count) swings, \(export.strokes.count) strokes."
                } catch {
                    message = "Import failed: \(error.localizedDescription)"
                }
            }
            .onChange(of: showCoursePicker) { _, showing in
                // A course left from a cancelled file picker is not used for the next import
                if showing { courseSelection = nil }
            }
    }
}
#endif
