import Foundation
import os
import SwiftData

enum Storage {
    /// The models each app saves.
    static let models: [any PersistentModel.Type] = [Round.self, StreamEntry.self, LogEntry.self]

    /// The app's saved data, on this device only: the phone's CloudKit container is for shared
    /// pins, and SwiftData would otherwise sync the store to it.
    ///
    /// UI tests empty it at launch, unless a test relaunches mid-round with `keepsRounds` and
    /// needs the round it saved. Every launch uses the same store, since watchOS can relaunch
    /// the app itself, without the test's arguments, to recover a running workout.
    static func container(for options: LaunchOptions) -> ModelContainer {
        let name = "default.store"
        if options.isUITesting, !options.keepsRounds {
            // SQLite keeps the store in three files
            for file in [name, name + "-shm", name + "-wal"] {
                try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: file))
            }
        }
        return container(ModelConfiguration(url: URL.applicationSupportDirectory.appending(path: name),
                                            cloudKitDatabase: .none))
    }

    /// An empty store kept in memory, for unit tests.
    static func inMemoryContainer() -> ModelContainer {
        container(ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private static func container(_ configuration: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(for: Schema(models), configurations: configuration)
        } catch {
            // Nothing works without the store, so there is nothing better to do than stop
            Log.storage.fault("Could not open the saved data: \(String(describing: error))")
            fatalError("Could not open the saved data: \(error)")
        }
    }
}
