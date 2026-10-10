import Foundation

/// Something that happened on the watch while a round was recording: the workout and the
/// sensors starting, stopping, failing and restarting. Written into the round's stream with the
/// fixes, so a round with no swings can be read for why. `value` means something different per
/// code, and is 0 where unused.
struct StreamEvent: Equatable {
    enum Code: UInt16, CaseIterable {
        case workoutStarted = 1
        /// Value: the recovered session's state.
        case workoutRecovered = 2
        /// Value: the new session state (`HKWorkoutSessionState`).
        case workoutState = 3
        /// Value: the `HKError` code.
        case workoutError = 4
        /// Value: the retry delay in seconds.
        case workoutRefused = 5
        /// Value: 1 by the watchdog, 2 forced by a stalled sensor, 3 the running flag was corrected.
        case workoutRestart = 6
        case workoutEnded = 7

        case swingDetectionStarted = 10
        case swingDetectionStopped = 11
        /// Value: readings in the batch.
        case accelerometerFirstBatch = 12
        /// Value: the `CMError` code.
        case accelerometerError = 13
        /// Value: restarts in a row with no data.
        case accelerometerRestart = 14
        /// Value: restarts in a row with no data.
        case accelerometerStalled = 15
        case accelerometerUnsupported = 16

        /// Value: the hole number.
        case contactsOn = 20
        /// Value: seconds on.
        case contactsOff = 21

        /// Value: readings in the batch.
        case deviceMotionFirstBatch = 30
        /// Value: the `CMError` code.
        case deviceMotionError = 31
        /// Value: restarts in a row with no data.
        case deviceMotionRestart = 32
        /// Value: restarts in a row with no data.
        case deviceMotionStalled = 33
        case deviceMotionUnsupported = 34

        case microphoneStarted = 40
        /// Value: 1 permission missing, 2 the start failed.
        case microphoneError = 41
        /// Value: restarts in a row with no data.
        case microphoneRestart = 42
        /// Value: restarts in a row with no data.
        case microphoneStalled = 43
    }

    let timestamp: Date
    let code: Code
    let value: Float

    init(timestamp: Date = Date(), code: Code, value: Float = 0) {
        self.timestamp = timestamp
        self.code = code
        self.value = value
    }

    /// The code's name, for exports and logs.
    var name: String { String(describing: code) }
}
