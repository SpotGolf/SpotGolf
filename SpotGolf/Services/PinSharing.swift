import Foundation
import CloudKit
import CoreLocation

/// Where shared pins are kept.
protocol PinSharing {
    /// True when the device has an iCloud account, which uploads need.
    func isAccountAvailable() async -> Bool
    /// Every hole's pin on a course on one day.
    func fetch(courseID: UUID, courseDate: String) async throws -> [SharedPin]
    /// Saves the hole's pin, replacing the one stored.
    func upload(_ pin: SharedPin) async throws
}

/// For UI tests, which run without iCloud: nothing is shared.
struct NoPinSharing: PinSharing {
    func isAccountAvailable() async -> Bool { false }
    func fetch(courseID: UUID, courseDate: String) async throws -> [SharedPin] { [] }
    func upload(_ pin: SharedPin) async throws {}
}

/// Shared pins in the app's CloudKit public database. Anyone can read them; signed-in users
/// can write any of them (the `Pin` record type's security roles, set in the CloudKit console).
final class CloudKitPinSharing: PinSharing {
    static let containerID = "iCloud.golf.spot.SpotGolf"
    static let recordType = "Pin"

    private let container: CKContainer

    init(container: CKContainer = CKContainer(identifier: CloudKitPinSharing.containerID)) {
        self.container = container
    }

    private var database: CKDatabase { container.publicCloudDatabase }

    func isAccountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    func fetch(courseID: UUID, courseDate: String) async throws -> [SharedPin] {
        let predicate = NSPredicate(format: "courseID == %@ AND courseDate == %@", courseID.uuidString, courseDate)
        // At most one record per hole, well inside one page of results
        let (results, _) = try await database.records(matching: CKQuery(recordType: Self.recordType, predicate: predicate))
        return results.compactMap { try? $0.1.get() }.compactMap(Self.pin(from:))
    }

    func upload(_ pin: SharedPin) async throws {
        // Replaces whatever is stored for the hole: the last pin set wins
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: pin.recordName))
        record["courseID"] = pin.courseID.uuidString
        record["subCourse"] = pin.subCourse
        record["holeNumber"] = pin.holeNumber
        record["courseDate"] = pin.courseDate
        record["location"] = CLLocation(latitude: pin.latitude, longitude: pin.longitude)
        record["setAt"] = pin.setAt
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    private static func pin(from record: CKRecord) -> SharedPin? {
        guard let courseID = (record["courseID"] as? String).flatMap(UUID.init(uuidString:)),
              let subCourse = record["subCourse"] as? String,
              let holeNumber = record["holeNumber"] as? Int,
              let courseDate = record["courseDate"] as? String,
              let location = record["location"] as? CLLocation,
              let setAt = record["setAt"] as? Date else { return nil }
        return SharedPin(courseID: courseID, subCourse: subCourse, holeNumber: holeNumber, courseDate: courseDate,
                         latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, setAt: setAt)
    }
}
