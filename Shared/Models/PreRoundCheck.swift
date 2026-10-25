import Foundation

/// Something the watch's pre-round checks found would not work during the round. Missing
/// permissions are their own refusal reason, so the phone can say how to grant each one.
enum CheckFailure: Codable, Equatable {
    /// What was wrong with a sensor.
    enum SensorProblem: String, Codable {
        /// It could not be started.
        case notStarted
        /// It started but sent nothing in time.
        case noData
        /// It sent only data that is not real: zeros, silence or NaNs.
        case notReal
    }

    /// The workout session, which keeps the app running and turns on the motion sensors, did not run in time.
    case workoutNotRunning
    /// `sensor` is the input's name: accelerometer, deviceMotion or microphone.
    case sensor(String, SensorProblem)
    /// No GPS fix arrived in time.
    case noLocation

    /// One line for the phone's banner.
    var text: String {
        switch self {
        case .workoutNotRunning:
            String(localized: "The workout did not start")
        case .noLocation:
            String(localized: "No GPS fix")
        case .sensor(let name, let problem):
            switch problem {
            case .notStarted: String(localized: "\(Self.title(of: name)) did not start")
            case .noData: String(localized: "\(Self.title(of: name)) sent no data")
            case .notReal: String(localized: "\(Self.title(of: name)) is not working")
            }
        }
    }

    private static func title(of sensor: String) -> String {
        switch sensor {
        case "accelerometer": String(localized: "Accelerometer")
        case "deviceMotion": String(localized: "Gyroscope")
        case "microphone": String(localized: "Microphone")
        default: sensor
        }
    }
}

/// Where the watch's pre-round checks are for one round.
enum PreRoundCheckState: Equatable {
    case notRun
    case running
    case passed
    /// Missing permissions, or `checksFailed`.
    case failed(StartRoundRefused.Reason)
}
