import Foundation

/// Ball contact the watch detected: a click and an accelerometer burst at the same instant
/// while the wrist was turning. See `ContactDetector` for the numbers.
struct ContactEvent: Equatable {
    let timestamp: Date
    /// Burst × click. The phone calls 2.7 or more a putt, and 1.2 or more a tap-in after one.
    let score: Float
    /// The accelerometer's high-frequency residual at the instant, in g.
    let burst: Float
    /// The loudest millisecond of high-passed audio within 4 ms, as a multiple of the background.
    let click: Float
    /// Mean rotation rate over the 100 ms before, in rad/s.
    let turning: Float
}
