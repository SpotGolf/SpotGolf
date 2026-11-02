import CoreGraphics
import Foundation

/// Where everything in the launch splash is at a time since it appeared. A ball flies in with a
/// tracer, lands and hops, the pin grows up out of it, then the title shows. Points are in a
/// 200 × 420 design space; `SplashView` scales it to fit the screen. See
/// `plans/2026-11-02-splash-screen.md`.
enum SplashTimeline {
    /// The design space, fitted to the screen and centered.
    static let size = CGSize(width: 200, height: 420)
    /// Where the pin's tip stands, under the landed ball.
    static let pinTip = CGPoint(x: 100, y: 258)
    /// When the ball lands, with a haptic tap.
    static let landing: TimeInterval = 0.85
    /// When the splash starts to fade out to the app, after holding the finished splash.
    static let end: TimeInterval = 3.0
    /// When each ring starts to spread over the ground: as the ball lands, and as the pin stands up.
    static let ringStarts: [TimeInterval] = [landing, 1.05]
    /// The most the splash's clock moves for one frame. The app is busy for a moment after launch
    /// and draws no frames, so the animation waits it out instead of skipping ahead.
    static let longestFrame: TimeInterval = 1.0 / 30

    // The flight is a quadratic curve from the bottom left, high over the top, to the ball
    // resting on the pin's tip
    private static let tee = CGPoint(x: 18, y: 400)
    private static let apex = CGPoint(x: 30, y: -80)
    private static let rest = CGPoint(x: 100, y: 254)

    /// Whether the splash shows: not under UI tests, which run at machine speed, and not when the
    /// player asked for less motion.
    static func shows(isUITesting: Bool, reducesMotion: Bool) -> Bool {
        !isUITesting && !reducesMotion
    }

    /// The splash's time after a frame `step` long, which counts for no more than `longestFrame`.
    static func advance(_ time: TimeInterval, by step: TimeInterval) -> TimeInterval {
        time + min(max(step, 0), longestFrame)
    }

    /// How far along its flight the ball is, from 0 at the tee to 1 landed. It slows as it comes down.
    static func flight(at time: TimeInterval) -> Double {
        1 - pow(1 - progress(time, from: 0, to: landing), 1.6)
    }

    /// The point `fraction` of the way along the flight.
    static func point(alongFlight fraction: Double) -> CGPoint {
        let a = (1 - fraction) * (1 - fraction)
        let b = 2 * (1 - fraction) * fraction
        let c = fraction * fraction
        return CGPoint(x: a * tee.x + b * apex.x + c * rest.x, y: a * tee.y + b * apex.y + c * rest.y)
    }

    /// The ball's center, with one small hop where it lands.
    static func ballCenter(at time: TimeInterval) -> CGPoint {
        var center = point(alongFlight: flight(at: time))
        let hop = progress(time, from: landing, to: landing + 0.2)
        if hop > 0, hop < 1 {
            center.y -= 8 * sin(.pi * hop)
        }
        return center
    }

    /// The ball shrinks as it flies away from the player.
    static func ballRadius(at time: TimeInterval) -> Double {
        7 - 3 * flight(at: time)
    }

    /// The ball fades in as it leaves the tee, so the first frame is the launch screen's plain
    /// color, and fades out as the pin grows up out of it.
    static func ballOpacity(at time: TimeInterval) -> Double {
        progress(time, from: 0, to: 0.1) * (1 - progress(time, from: 1.0, to: 1.15))
    }

    /// The part of the flight the tracer covers, as fractions, and how strongly it shows. It
    /// follows the ball, then shrinks toward the pin and fades after the landing.
    static func tracer(at time: TimeInterval) -> (start: Double, end: Double, opacity: Double) {
        let flight = flight(at: time)
        guard time >= landing else {
            return (max(0, flight - 0.55), flight, 1)
        }
        let fade = progress(time, from: landing, to: 1.4)
        return (0.45 + 0.55 * fade, 1, 1 - fade)
    }

    /// How much the pin has grown, from 0 to 1, overshooting a little before it settles.
    static func pinScale(at time: TimeInterval) -> Double {
        let grow = progress(time, from: 1.0, to: 1.35)
        guard grow > 0 else {
            return 0
        }
        // Ease out with an overshoot
        let overshoot = 1.70158
        return 1 + (overshoot + 1) * pow(grow - 1, 3) + overshoot * pow(grow - 1, 2)
    }

    /// A ring's radius across and how strongly it shows, or nil before it starts and after it has faded.
    static func ring(startingAt start: TimeInterval, at time: TimeInterval) -> (radius: Double, opacity: Double)? {
        let spread = (time - start) / 0.9
        guard spread >= 0, spread <= 1 else {
            return nil
        }
        return (6 + 90 * easeOut(spread), 0.8 * (1 - spread))
    }

    /// How far the title has risen into place and faded in, from 0 to 1.
    static func title(at time: TimeInterval) -> Double {
        easeOut(progress(time, from: 1.2, to: 1.6))
    }

    /// How strongly the launch screen's plain color still covers the gradient. iOS shows that color
    /// before the app runs, so the splash starts on it and blends into the gradient.
    static func launchColor(at time: TimeInterval) -> Double {
        1 - progress(time, from: 0, to: 0.25)
    }

    /// How far `time` is from `start` to `end`, from 0 to 1.
    private static func progress(_ time: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Double {
        min(max((time - start) / (end - start), 0), 1)
    }

    private static func easeOut(_ fraction: Double) -> Double {
        1 - pow(1 - fraction, 3)
    }
}
