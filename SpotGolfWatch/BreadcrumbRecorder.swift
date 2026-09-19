import CoreLocation
import Foundation

@MainActor
class BreadcrumbRecorder: ObservableObject {
    struct Breadcrumb {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
    }

    @Published private(set) var isStationary = false

    private var breadcrumbs: [Breadcrumb] = []
    private var cumulativeDistance: Double = 0 // meters since last mark
    private var lastMarkTime: Date?
    private var lastHapticLocation: CLLocation?
    private var stationaryThreshold: TimeInterval = 30
    private let movementThreshold: Double = 3 // meters — below this is "not moving"

    private var lastKnownLocation: CLLocation?
    private var timer: Timer?

    var cumulativeYards: Double {
        cumulativeDistance * 1.09361
    }

    var timeSinceLastMark: TimeInterval? {
        guard let lastMarkTime else { return nil }
        return Date().timeIntervalSince(lastMarkTime)
    }

    func updateThreshold(_ threshold: TimeInterval) {
        stationaryThreshold = threshold
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call on every location update to keep the last known position fresh and track movement.
    func updateLocation(_ location: CLLocation) {
        if let prev = lastKnownLocation {
            cumulativeDistance += location.distance(from: prev)
        }
        lastKnownLocation = location
    }

    private func tick() {
        guard let location = lastKnownLocation else { return }
        let now = Date()

        breadcrumbs.append(Breadcrumb(coordinate: location.coordinate, timestamp: now))

        // Detect stationary: check if all breadcrumbs in the threshold window are within movementThreshold
        let windowStart = now.addingTimeInterval(-stationaryThreshold)
        let windowBreadcrumbs = breadcrumbs.filter { $0.timestamp >= windowStart }

        if windowBreadcrumbs.count >= 2,
           let first = windowBreadcrumbs.first,
           now.timeIntervalSince(first.timestamp) >= stationaryThreshold {
            let maxSpread = Self.maxSpread(windowBreadcrumbs)
            isStationary = maxSpread < movementThreshold
        } else {
            isStationary = false
        }

        // Trim old breadcrumbs beyond the window
        breadcrumbs.removeAll { $0.timestamp < windowStart.addingTimeInterval(-5) }
    }

    /// Returns any unconsumed stationary location before resetting. The caller should
    /// process this as a missed mark guess before the breadcrumb context is lost.
    @discardableResult
    func markPlaced() -> CLLocationCoordinate2D? {
        let pending = consumeStationaryLocation()
        lastMarkTime = Date()
        cumulativeDistance = 0
        breadcrumbs.removeAll()
        isStationary = false
        return pending
    }

    /// Returns the current stationary location if stationary, then clears breadcrumbs used to determine it.
    func consumeStationaryLocation() -> CLLocationCoordinate2D? {
        guard isStationary, let last = breadcrumbs.last else { return nil }

        // Check if we already fired a haptic at this location
        let loc = CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        if let lastHaptic = lastHapticLocation, loc.distance(from: lastHaptic) < 10 {
            return nil
        }
        lastHapticLocation = loc

        // Keep only the most recent breadcrumb; discard the rest
        let coord = last.coordinate
        breadcrumbs = [breadcrumbs.last!]
        isStationary = false
        return coord
    }

    func reset() {
        stop()
        breadcrumbs.removeAll()
        cumulativeDistance = 0
        lastMarkTime = nil
        lastHapticLocation = nil
        lastKnownLocation = nil
        isStationary = false
    }

    private static func maxSpread(_ breadcrumbs: [Breadcrumb]) -> Double {
        guard let first = breadcrumbs.first else { return 0 }
        let origin = CLLocation(latitude: first.coordinate.latitude, longitude: first.coordinate.longitude)
        return breadcrumbs.dropFirst().map { crumb in
            CLLocation(latitude: crumb.coordinate.latitude, longitude: crumb.coordinate.longitude)
                .distance(from: origin)
        }.max() ?? 0
    }
}
