import Foundation
import os

/// The app's log, one category per area. Every line goes two ways: to Apple's unified log,
/// where Xcode's console and Console.app show it, and to `sink`, which `LogStore` sets so the
/// line is saved in the app's own store and read after a round. See plans/2026-10-10-app-log.md.
///
/// - Failures use `error`, key events `notice`, and detail that only helps when something is
///   being chased `debug`. Debug lines are saved only while `isDebugEnabled` is on.
/// - Lines written before the sink is set, such as the store failing to open, are held and
///   handed to the sink when it is set.
/// - Nothing may log per sensor batch or per GPS fix: a round's log stays small because it
///   only holds events.
enum Log {
    static let subsystem = "golf.spot.SpotGolf"

    static let contacts = LogCategory("contacts")
    static let courses = LogCategory("courses")
    static let export = LogCategory("export")
    static let liveActivity = LogCategory("liveActivity")
    static let location = LogCategory("location")
    static let permissions = LogCategory("permissions")
    static let pins = LogCategory("pins")
    static let puttLab = LogCategory("puttLab")
    static let rounds = LogCategory("rounds")
    static let sensors = LogCategory("sensors")
    static let storage = LogCategory("storage")
    static let swings = LogCategory("swings")
    static let sync = LogCategory("sync")
    static let workout = LogCategory("workout")

    #if os(watchOS)
    static let device = LogDevice.watch
    #else
    static let device = LogDevice.phone
    #endif

    /// Lines held until the sink is set. Launch writes a handful; this is well above it.
    static let heldLineLimit = 500

    private struct State {
        var sink: (@Sendable (LogLine) -> Void)?
        var held: [LogLine] = []
        var isDebugEnabled = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// Whether `debug` lines are written. Set from the Debug Logging setting.
    static var isDebugEnabled: Bool {
        get { state.withLock { $0.isDebugEnabled } }
        set { state.withLock { $0.isDebugEnabled = newValue } }
    }

    /// Where lines go once the app's store is open. Held lines are handed over first, in order.
    /// Nil holds lines again, which only tests do.
    static func setSink(_ sink: (@Sendable (LogLine) -> Void)?) {
        let held = state.withLock { state -> [LogLine] in
            state.sink = sink
            guard sink != nil else { return [] }
            defer { state.held = [] }
            return state.held
        }
        for line in held {
            sink?(line)
        }
    }

    fileprivate static func write(_ line: LogLine) {
        let sink = state.withLock { state -> (@Sendable (LogLine) -> Void)? in
            if let sink = state.sink { return sink }
            state.held.append(line)
            if state.held.count > heldLineLimit {
                state.held.removeFirst(state.held.count - heldLineLimit)
            }
            return nil
        }
        sink?(line)
    }
}

/// One area's log. Each call writes one `LogLine`.
struct LogCategory: Sendable {
    let name: String
    private let logger: Logger

    init(_ name: String) {
        self.name = name
        logger = Logger(subsystem: Log.subsystem, category: name)
    }

    /// Detail for chasing a problem. Written only while `Log.isDebugEnabled`; the text is not
    /// built otherwise.
    func debug(_ message: @autoclosure () -> String) {
        guard Log.isDebugEnabled else { return }
        write(.debug, message())
    }

    /// A key event.
    func notice(_ message: String) {
        write(.notice, message)
    }

    /// A failure the app goes on from.
    func error(_ message: String) {
        write(.error, message)
    }

    /// A failure the app cannot go on from.
    func fault(_ message: String) {
        write(.fault, message)
    }

    private func write(_ level: LogLevel, _ message: String) {
        logger.log(level: level.osLogType, "\(message, privacy: .public)")
        Log.write(LogLine(timestamp: Date(), device: Log.device, level: level, category: name, message: message))
    }
}

enum LogLevel: String, Codable, Equatable, Sendable, CaseIterable {
    case debug, notice, error, fault

    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .notice: .default
        case .error: .error
        case .fault: .fault
        }
    }

    /// The letter in an exported line.
    var letter: String {
        switch self {
        case .debug: "D"
        case .notice: "N"
        case .error: "E"
        case .fault: "F"
        }
    }

    /// An error or a fault.
    var isFailure: Bool {
        self == .error || self == .fault
    }
}

enum LogDevice: String, Codable, Equatable, Sendable, CaseIterable {
    case phone, watch
}

/// One line of the log, with where and when it was written.
struct LogLine: Codable, Equatable, Sendable {
    let timestamp: Date
    let device: LogDevice
    let level: LogLevel
    let category: String
    let message: String

    /// The line as exported: `2026-10-09T16:12:33.123Z watch E sensors accelerometer …`.
    var text: String {
        "\(timestamp.formatted(Self.timeFormat)) \(device.rawValue) \(level.letter) \(category) \(message)"
    }

    static let timeFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
