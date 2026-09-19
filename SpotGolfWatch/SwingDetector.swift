import CoreMotion
import CoreLocation
import Foundation

@MainActor
class SwingDetector: ObservableObject {
    struct SwingEvent {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
    }

    @Published private(set) var lastSwing: SwingEvent?

    private let motionManager = CMMotionManager()
    private var isRunning = false
    static let accelerationThreshold: Double = 10.0 // g-force

    // Cooldown to avoid multiple detections from a single swing
    private var lastSwingTime: Date?
    private static let cooldown: TimeInterval = 3

    func start() {
        guard !isRunning, motionManager.isAccelerometerAvailable else { return }
        isRunning = true
        motionManager.accelerometerUpdateInterval = 1.0 / 50.0 // 50 Hz
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                self.processAcceleration(data)
            }
        }
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
        isRunning = false
    }

    /// Call this with the current location so swing events can be tagged with position.
    private var currentLocation: CLLocationCoordinate2D?

    func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        currentLocation = coordinate
    }

    func consumeSwing() -> SwingEvent? {
        let swing = lastSwing
        lastSwing = nil
        return swing
    }

    private func processAcceleration(_ data: CMAccelerometerData) {
        let accel = data.acceleration
        let magnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)

        guard magnitude >= Self.accelerationThreshold else { return }

        let now = Date()
        if let last = lastSwingTime, now.timeIntervalSince(last) < Self.cooldown { return }
        lastSwingTime = now

        guard let coord = currentLocation else { return }
        lastSwing = SwingEvent(coordinate: coord, timestamp: now)
    }
}
