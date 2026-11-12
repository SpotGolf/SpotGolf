import SwiftUI
import UIKit

/// A one-finger drag that starts on the Caddie's shot pattern and moves it. A drag that starts
/// anywhere else fails at once, so the map pans as before, and taps and long presses on the pattern
/// still go to the map. See plans/2026-11-02-caddie-club-and-aim.md, section 1.
struct CaddieDragGesture<Space: CoordinateSpaceProtocol>: UIGestureRecognizerRepresentable {
    /// The space the points are in.
    let space: Space
    /// True for a point on the pattern.
    let isOnPattern: (CGPoint) -> Bool
    /// The finger went down at the first point and is now at the second.
    let changed: (_ start: CGPoint, _ finger: CGPoint) -> Void
    /// The finger lifted, or the system cancelled the drag.
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        // Two fingers zoom and turn the map
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isOnPattern = isOnPattern
        context.coordinator.space = space
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let finger = context.converter.location(in: space)
        switch recognizer.state {
        case .began:
            let start = context.coordinator.start(of: finger)
            context.coordinator.startPoint = start
            changed(start, finger)
        case .changed:
            changed(context.coordinator.startPoint ?? finger, finger)
        case .ended, .cancelled, .failed:
            context.coordinator.startPoint = nil
            ended()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter
        var isOnPattern: (CGPoint) -> Bool = { _ in false }
        var space: Space?
        /// Where the finger went down, for the drag under way.
        var startPoint: CGPoint?

        init(converter: CoordinateSpaceConverter) {
            self.converter = converter
        }

        /// Where the finger went down: a pan starts only once the finger has moved a little.
        func start(of finger: CGPoint) -> CGPoint {
            guard let space, let moved = converter.translation(in: space) else { return finger }
            return CGPoint(x: finger.x - moved.x, y: finger.y - moved.y)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let space else { return false }
            return isOnPattern(start(of: converter.location(in: space)))
        }

        /// The map's own pan waits for this one to fail, so a drag on the pattern never pans it.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer !== gestureRecognizer
        }
    }
}
