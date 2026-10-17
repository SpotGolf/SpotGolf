import Foundation

/// Ball contact the watch detected: a click with an accelerometer burst just after it, at the
/// end of a putting stroke. See `ContactDetector` and `StrokeGate` for the numbers.
struct ContactEvent: Equatable {
    let timestamp: Date
    /// Burst × click. The phone calls 2.7 or more a putt, and 1.2 or more a tap-in after one.
    let score: Float
    /// The accelerometer's high-frequency residual at the instant, in g.
    let burst: Float
    /// The loudest millisecond of high-passed audio in the 25 ms up to the burst, as a multiple of
    /// the background.
    let click: Float
    /// Mean rotation rate over the 100 ms before, in rad/s.
    let turning: Float
    /// The watch's `StrokeGate` passed it: it came at the end of a putting stroke. Watches from
    /// before the gate recorded every contact over the score floor, and the phone keeps its
    /// older rules for those.
    var gated = false
}
