import Foundation

@MainActor
class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            if settings != oldValue {
                save()
                onSettingsChanged?(settings)
            }
        }
    }

    var onSettingsChanged: ((AppSettings) -> Void)?

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("settings.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.settingsFileURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = .default
        }
    }

    private static var settingsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("settings.json")
    }

    func apply(_ newSettings: AppSettings) {
        settings = newSettings
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
}
