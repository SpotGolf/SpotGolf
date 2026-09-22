import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var syncService: SyncService
    @Environment(\.dismiss) private var dismiss

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
                    Text("Mark Suggestions")
                } footer: {
                    Text("How long you must be stationary before a mark suggestion is created.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: settingsStore.settings) {
                syncService.send(.updateSettings(settingsStore.settings))
            }
        }
    }
}
