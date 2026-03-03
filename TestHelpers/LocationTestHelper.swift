import CoreLocation
import Foundation
import XCTest

struct TestLocation {
    let latitude: Double
    let longitude: Double
    let hole: Int
}

enum LocationTestHelper {

    /// Loads test GPS coordinates from `test-locations.csv` bundled in the test target.
    /// Each row is `latitude,longitude`.
    static func loadTestLocations(for bundle: Bundle = .init(for: BundleToken.self)) -> [TestLocation] {
        guard let url = bundle.url(forResource: "test-locations", withExtension: "csv"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Missing test-locations.csv in test bundle")
        }

        return contents
            .split(separator: "\n")
            .compactMap { line -> TestLocation? in
                let parts = line.split(separator: ",")
                guard parts.count >= 2,
                      let lat = Double(parts[0]),
                      let lon = Double(parts[1]) else { return nil }
                let hole = parts.count >= 3 ? Int(parts[2]) ?? 1 : 1
                return TestLocation(latitude: lat, longitude: lon, hole: hole)
            }
    }

    /// Sets the simulator's GPS location using XCUIDevice.
    static func setSimulatorLocation(latitude: Double, longitude: Double) {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        XCUIDevice.shared.location = XCUILocation(location: location)
    }
}

/// Anchor class so `Bundle(for:)` resolves to the test bundle containing this file.
final class BundleToken {}
