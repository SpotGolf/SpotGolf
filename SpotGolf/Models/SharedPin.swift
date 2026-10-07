import Foundation
import CoreLocation

/// One hole's pin as golfers share it: one per hole per day. See plans/2026-10-06-shared-pins.md.
struct SharedPin: Equatable {
    let courseID: UUID
    /// The nine's name and the hole's number, the same on every phone.
    let subCourse: String
    let holeNumber: Int
    /// `yyyy-MM-dd` where the pin was set: pins move every day.
    let courseDate: String
    let latitude: Double
    let longitude: Double
    let setAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// One record per hole per day, so each save replaces the hole's pin.
    var recordName: String {
        let nine = subCourse.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? subCourse
        return "\(courseID.uuidString)-\(nine)-\(holeNumber)-\(courseDate)"
    }

    static func courseDate(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension Round {
    /// A pin set on this round, as shared with other golfers, or nil when its hole is not on the course.
    func sharedPin(for pin: PinLocation) -> SharedPin? {
        guard let key = courseSelection.holeKey(at: pin.holeIndex) else { return nil }
        return SharedPin(courseID: course.id, subCourse: key.subCourse, holeNumber: key.number,
                         courseDate: SharedPin.courseDate(for: pin.setAt),
                         latitude: pin.latitude, longitude: pin.longitude, setAt: pin.setAt)
    }

    /// Other golfers' pins as this round's pins, leaving out holes the round does not play and
    /// pins not on their hole's green.
    func pins(from shared: [SharedPin]) -> [PinLocation] {
        shared.compactMap { pin in
            guard let index = courseSelection.holeIndex(subCourse: pin.subCourse, number: pin.holeNumber),
                  isOnGreen(pin.coordinate, holeIndex: index) else { return nil }
            return PinLocation(holeIndex: index, coordinate: pin.coordinate, setAt: pin.setAt, source: .shared)
        }
    }
}
