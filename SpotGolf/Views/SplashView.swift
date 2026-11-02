import SwiftUI

/// The launch splash, over the app on a cold launch: a ball flies in with a tracer, lands with a
/// haptic tap, and becomes the pin from the app icon, then the title shows. `SplashTimeline` says
/// where everything is. A tap skips it.
struct SplashView: View {
    /// Called when the splash is done or skipped, for the app to fade it out. May be called again
    /// while it fades.
    let onFinish: () -> Void

    @State private var clock = Clock()
    @State private var landed = false

    /// The splash's own time, moved on by each frame drawn (see `SplashTimeline.longestFrame`).
    /// Not observed: it only changes as the timeline draws a frame.
    @MainActor private final class Clock {
        private var lastFrame: Date?
        private var time: TimeInterval = 0

        func time(at frame: Date) -> TimeInterval {
            if let lastFrame {
                time = SplashTimeline.advance(time, by: frame.timeIntervalSince(lastFrame))
            }
            lastFrame = frame
            return time
        }
    }

    private static let gradient = Gradient(colors: [Color(hex: "#2FBF5E"), Color(hex: "#0D5225")])
    private static let launchColor = Color("LaunchBackground")
    private static let tracerColor = Color(hex: "#FFD84D")
    private static let pinColor = Color(hex: "#F4FAF5")
    private static let pinDotColor = Color(hex: "#95D9A9")

    /// The icon's pin, in the design space, with its tip on `SplashTimeline.pinTip`.
    private static let pin: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 100, y: 258))
        path.addCurve(to: CGPoint(x: 66, y: 190), control1: CGPoint(x: 80, y: 230), control2: CGPoint(x: 66, y: 210))
        path.addArc(center: CGPoint(x: 100, y: 190), radius: 34, startAngle: .degrees(180), endAngle: .degrees(0),
                    clockwise: false)
        path.addCurve(to: CGPoint(x: 100, y: 258), control1: CGPoint(x: 134, y: 210), control2: CGPoint(x: 120, y: 230))
        path.closeSubpath()
        return path
    }()
    private static let pinDot = Path(ellipseIn: CGRect(x: 87, y: 177, width: 26, height: 26))

    var body: some View {
        TimelineView(.animation) { context in
            let time = clock.time(at: context.date)
            Canvas { canvas, size in
                draw(at: time, in: &canvas, size: size)
            }
            .onChange(of: time >= SplashTimeline.landing) { _, hasLanded in
                landed = hasLanded
            }
            .onChange(of: time >= SplashTimeline.end) { _, isDone in
                if isDone {
                    onFinish()
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "SpotGolf"))
        .sensoryFeedback(.impact(weight: .medium), trigger: landed)
    }

    private func draw(at time: TimeInterval, in canvas: inout GraphicsContext, size: CGSize) {
        let screen = Path(CGRect(origin: .zero, size: size))
        canvas.fill(screen, with: .linearGradient(Self.gradient, startPoint: .zero,
                                                  endPoint: CGPoint(x: size.width, y: size.height)))
        canvas.fill(screen, with: .color(Self.launchColor.opacity(SplashTimeline.launchColor(at: time))))

        // The rest is drawn in the design space, fitted to the screen and centered
        let design = SplashTimeline.size
        let scale = min(size.width / design.width, size.height / design.height)
        canvas.translateBy(x: size.width / 2, y: size.height / 2)
        canvas.scaleBy(x: scale, y: scale)
        canvas.translateBy(x: -design.width / 2, y: -design.height / 2)

        drawTracer(at: time, in: canvas)
        drawRings(at: time, in: canvas)
        drawPin(at: time, in: canvas)

        let center = SplashTimeline.ballCenter(at: time)
        let radius = SplashTimeline.ballRadius(at: time)
        canvas.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(SplashTimeline.ballOpacity(at: time))))

        let rise = SplashTimeline.title(at: time)
        var title = canvas
        title.opacity = rise
        title.draw(Text(verbatim: "SpotGolf").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white),
                   at: CGPoint(x: 100, y: 312 + 10 * (1 - rise)))
    }

    /// The tracer, faint and thin at its tail and strong at the ball, over a soft glow.
    private func drawTracer(at time: TimeInterval, in canvas: GraphicsContext) {
        let tracer = SplashTimeline.tracer(at: time)
        guard tracer.end > tracer.start, tracer.opacity > 0 else {
            return
        }
        let segments = 24
        let stroke = { (canvas: GraphicsContext, widthScale: Double) in
            for index in 0..<segments {
                let from = tracer.start + (tracer.end - tracer.start) * Double(index) / Double(segments)
                let to = tracer.start + (tracer.end - tracer.start) * Double(index + 1) / Double(segments)
                let strength = Double(index + 1) / Double(segments)
                var segment = Path()
                segment.move(to: SplashTimeline.point(alongFlight: from))
                segment.addLine(to: SplashTimeline.point(alongFlight: to))
                canvas.stroke(segment, with: .color(Self.tracerColor.opacity(0.9 * strength * tracer.opacity)),
                              lineWidth: (1 + 2.5 * strength) * widthScale)
            }
        }
        canvas.drawLayer { glow in
            glow.addFilter(.blur(radius: 3))
            stroke(glow, 2.5)
        }
        stroke(canvas, 1)
    }

    /// The rings that spread over the ground from the pin's spot.
    private func drawRings(at time: TimeInterval, in canvas: GraphicsContext) {
        let tip = SplashTimeline.pinTip
        for start in SplashTimeline.ringStarts {
            guard let ring = SplashTimeline.ring(startingAt: start, at: time) else {
                continue
            }
            let ellipse = CGRect(x: tip.x - ring.radius, y: tip.y - ring.radius * 0.3, width: ring.radius * 2,
                                 height: ring.radius * 0.6)
            canvas.stroke(Path(ellipseIn: ellipse), with: .color(.white.opacity(ring.opacity)), lineWidth: 1.5)
        }
    }

    /// The pin and its shadow, grown up from the tip.
    private func drawPin(at time: TimeInterval, in canvas: GraphicsContext) {
        let scale = SplashTimeline.pinScale(at: time)
        guard scale > 0 else {
            return
        }
        let tip = SplashTimeline.pinTip
        let shadow = min(scale, 1)
        canvas.fill(Path(ellipseIn: CGRect(x: tip.x - 15 * shadow, y: tip.y + 4 - 3.5 * shadow, width: 30 * shadow,
                                           height: 7 * shadow)),
                    with: .color(.black.opacity(0.28 * shadow)))

        let grow = CGAffineTransform(translationX: tip.x, y: tip.y).scaledBy(x: scale, y: scale)
            .translatedBy(x: -tip.x, y: -tip.y)
        canvas.fill(Self.pin.applying(grow), with: .color(Self.pinColor))
        canvas.fill(Self.pinDot.applying(grow), with: .color(Self.pinDotColor))
    }
}
