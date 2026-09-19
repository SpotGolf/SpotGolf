import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var syncService: SyncService
    @Environment(\.dismiss) private var dismiss

    private let thresholdOptions = stride(from: 0, through: 120, by: 5).map { $0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Missed Mark Guesses", isOn: $settingsStore.settings.missedMarkGuessesEnabled)
                } footer: {
                    Text("Detects when you may have forgotten to mark your ball and suggests possible locations.")
                }

                if settingsStore.settings.missedMarkGuessesEnabled {
                    Section {
                        Toggle("Haptic Reminders", isOn: $settingsStore.settings.hapticEnabled)
                    } footer: {
                        Text("Tap your wrist when you stop moving and haven't marked your ball recently.")
                    }

                    Section {
                        Picker("Stationary Threshold", selection: $settingsStore.settings.stationaryThreshold) {
                            ForEach(thresholdOptions, id: \.self) { seconds in
                                Text("\(seconds)s").tag(TimeInterval(seconds))
                            }
                        }
                    } footer: {
                        Text("How long you must be stationary before a missed mark guess is created.")
                    }
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
