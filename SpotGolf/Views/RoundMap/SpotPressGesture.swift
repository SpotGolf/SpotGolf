import SwiftUI
import UIKit

/// A long press that holds a spot, a new one or one already placed, until the finger lifts. It
/// reports the spot from the moment the press is recognized, before the finger moves, which
/// SwiftUI's long press followed by a drag does not on the map. See `SpotDrag`.
struct SpotPressGesture<Space: CoordinateSpaceProtocol>: UIGestureRecognizerRepresentable {
    let minimumDuration: TimeInterval
    /// The space the spot is held in.
    let space: Space
    /// How far a spot that follows the finger stands above it.
    let lift: CGFloat
    /// Where the held spot's dot is when the press is recognized. Nil for a new spot, whose dot
    /// is the press.
    var dot: () -> CGPoint? = { nil }
    /// The spot was picked up or moved. Its rise above the finger is animated.
    let changed: (SpotDrag) -> Void
    /// The finger lifted, with where the spot lands. Nil when the system cancelled the press.
    let ended: (SpotDrag?) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let finger = context.converter.location(in: space)
        switch recognizer.state {
        case .began:
            let drag = SpotDrag(dot: dot() ?? finger, press: finger, lift: lift)
            context.coordinator.drag = drag
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            changed(drag)
        case .changed:
            guard var drag = context.coordinator.drag else { return }
            let rises = drag.fingerMoved(to: finger)
            context.coordinator.drag = drag
            withAnimation(rises ? .easeOut(duration: 0.15) : nil) {
                changed(drag)
            }
        case .ended:
            ended(context.coordinator.drag)
            context.coordinator.drag = nil
        case .cancelled, .failed:
            ended(nil)
            context.coordinator.drag = nil
        default:
            break
        }
    }

    /// The spot held by the press under way.
    final class Coordinator {
        var drag: SpotDrag?
    }
}
