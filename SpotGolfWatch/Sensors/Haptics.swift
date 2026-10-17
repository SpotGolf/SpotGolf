import WatchKit

extension SensorInputs {
    /// Plays a haptic. A haptic shakes the watch like a tap, and has made contacts scoring up
    /// to 1130, so the detectors ignore readings around it, and around the tap that played it.
    /// Every haptic goes through here.
    func play(_ haptic: WKHapticType) {
        tapped()
        WKInterfaceDevice.current().play(haptic)
    }
}
