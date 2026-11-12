import Foundation

/// Random numbers from a seed, by SplitMix64: the same seed gives the same numbers, so a shot
/// pattern never changes between draws and the tests are steady.
struct SeededRandom {
    private var state: UInt64
    /// The second bell-curve value of the last pair made, for the next call.
    private var spare: Double?

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// From 0 up to, but not, 1.
    mutating func uniform() -> Double {
        Double(next() >> 11) * 0x1p-53
    }

    /// From the standard bell curve, by Box–Muller.
    mutating func normal() -> Double {
        if let value = spare {
            spare = nil
            return value
        }
        // 1 − u is above 0, so its log is finite
        let radius = (-2 * log(1 - uniform())).squareRoot()
        let angle = 2 * Double.pi * uniform()
        spare = radius * sin(angle)
        return radius * cos(angle)
    }
}
