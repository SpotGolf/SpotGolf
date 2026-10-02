import os

/// Loggers for Apple's unified log, one per area. Both apps use the same subsystem, so one
/// filter shows everything.
///
/// - Failures use `.error` and key events use `.notice`. The system saves both on the device,
///   so they can be read after a round: `sudo log collect --device` for the phone, or a
///   sysdiagnose for the watch, then open the archive in Console.app.
/// - Values in messages must be marked `privacy: .public`, or they show as `<private>` in
///   saved logs.
enum Log {
    static let subsystem = "golf.spot.SpotGolf"

    static let courses = Logger(subsystem: subsystem, category: "courses")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let liveActivity = Logger(subsystem: subsystem, category: "liveActivity")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let rounds = Logger(subsystem: subsystem, category: "rounds")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let swings = Logger(subsystem: subsystem, category: "swings")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let workout = Logger(subsystem: subsystem, category: "workout")
}
