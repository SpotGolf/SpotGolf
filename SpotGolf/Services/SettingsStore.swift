import Foundation
import Observation
import os

@MainActor
@Observable
class SettingsStore {
    var settings: AppSettings {
        didSet {
            if settings != oldValue {
                save()
            }
        }
    }

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("settings.json")
    }

    init() {
        do {
            settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: Self.settingsFileURL))
        } catch CocoaError.fileReadNoSuchFile {
            settings = .default
        } catch {
            Log.storage.error("Discarding saved settings: \(String(describing: error), privacy: .public)")
            settings = .default
        }
    }

    private static var settingsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("settings.json")
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL)
        } catch {
            Log.storage.error("Could not save settings: \(String(describing: error), privacy: .public)")
        }
    }
}
