import Foundation
import CoreLocation

enum TrackSource: String {
    case phone
    case watch

    /// The device this code is running on.
    static var current: TrackSource {
        #if os(watchOS)
        return .watch
        #else
        return .phone
        #endif
    }
}

/// One raw GPS fix recorded during a round.
struct TrackPoint: Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double? // meters, nil when the fix has no valid altitude
    let horizontalAccuracy: Double? // meters, nil when the fix has no valid accuracy

    /// Bytes per fix: timestamp (8), latitude (4), longitude (4), altitude (4), accuracy (4).
    static let recordSize = 24

    // Degrees are stored as whole numbers of 1e-7 degrees, about 1 cm
    private static let degreeScale = 10_000_000.0

    // Altitude and accuracy are stored as whole centimeters
    private static let centimeterScale = 100.0
    private static let unknownValue = Int32.min

    init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double?,
         horizontalAccuracy: Double? = nil) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
    }

    init(location: CLLocation) {
        self.init(timestamp: location.timestamp,
                  latitude: location.coordinate.latitude,
                  longitude: location.coordinate.longitude,
                  altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                  horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil)
    }

    /// One fixed-size record, little-endian: milliseconds since 1970 (Int64), then
    /// latitude and longitude in 1e-7 degrees, altitude and accuracy in centimeters (Int32 each).
    var record: Data {
        var data = Data(capacity: Self.recordSize)
        data.append(littleEndian: Int64((timestamp.timeIntervalSince1970 * 1000).rounded()))
        data.append(littleEndian: Int32((latitude * Self.degreeScale).rounded()))
        data.append(littleEndian: Int32((longitude * Self.degreeScale).rounded()))
        data.append(littleEndian: altitude.map { Int32(($0 * Self.centimeterScale).rounded()) } ?? Self.unknownValue)
        data.append(littleEndian: horizontalAccuracy.map { Int32(($0 * Self.centimeterScale).rounded()) } ?? Self.unknownValue)
        return data
    }

    /// Returns nil unless `record` is exactly one record.
    init?(record: Data) {
        guard record.count == Self.recordSize else { return nil }
        let milliseconds: Int64 = record.littleEndianInteger(at: 0)
        let latitude: Int32 = record.littleEndianInteger(at: 8)
        let longitude: Int32 = record.littleEndianInteger(at: 12)
        let altitude: Int32 = record.littleEndianInteger(at: 16)
        let accuracy: Int32 = record.littleEndianInteger(at: 20)
        self.init(timestamp: Date(timeIntervalSince1970: Double(milliseconds) / 1000),
                  latitude: Double(latitude) / Self.degreeScale,
                  longitude: Double(longitude) / Self.degreeScale,
                  altitude: altitude == Self.unknownValue ? nil : Double(altitude) / Self.centimeterScale,
                  horizontalAccuracy: accuracy == Self.unknownValue ? nil : Double(accuracy) / Self.centimeterScale)
    }
}

extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Reads an integer stored little-endian `offset` bytes from the start.
    func littleEndianInteger<T: FixedWidthInteger>(at offset: Int) -> T {
        T(littleEndian: withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) })
    }
}
