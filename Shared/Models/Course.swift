import Foundation
import CoreLocation

// MARK: - CourseCoordinate

struct CourseCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

// MARK: - CourseGreen

struct CourseGreen: Codable, Equatable {
    let front: CourseCoordinate
    let middle: CourseCoordinate
    let back: CourseCoordinate
}

// MARK: - FeatureType

enum FeatureType: String, Codable, Equatable {
    case bunker
    case water
}

// MARK: - CourseFeature

struct CourseFeature: Identifiable, Codable, Equatable {
    let id: String
    let type: FeatureType
    let front: CourseCoordinate
    let back: CourseCoordinate

    var middle: CLLocation {
        let lat = (front.latitude + back.latitude) / 2.0
        let lon = (front.longitude + back.longitude) / 2.0
        return CLLocation(latitude: lat, longitude: lon)
    }

    static func == (lhs: CourseFeature, rhs: CourseFeature) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.front == rhs.front &&
        lhs.back == rhs.back
    }
}

// MARK: - CourseHole

struct CourseHole: Identifiable, Codable, Equatable {
    let id: String
    let number: Int
    let par: Int
    let maleHandicap: Int?
    let femaleHandicap: Int?
    let green: CourseGreen
    let tees: [String: CourseCoordinate]
    let yardages: [String: Int]
    let features: [CourseFeature]
}

// MARK: - SubCourse

struct SubCourse: Codable, Equatable {
    let name: String?
    let holes: [CourseHole]
}

// MARK: - CourseLocation

struct CourseLocation: Codable, Equatable {
    let address: String?
    let city: String
    let coordinate: CourseCoordinate
    let country: String
    let state: String
}

// MARK: - Course

struct Course: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let clubName: String
    let location: CourseLocation
    let subCourses: [SubCourse]
}

// MARK: - CourseIndexLocation

struct CourseIndexLocation: Codable, Equatable {
    let coordinate: CourseCoordinate
    let city: String
    let state: String
    let country: String
}

// MARK: - CourseIndexEntry

struct CourseIndexEntry: Codable, Equatable {
    let name: String
    let clubName: String
    let location: CourseIndexLocation
    let path: String
}

// MARK: - CourseSelection

struct CourseSelection: Codable, Equatable {
    let course: Course
    let selectedSubCourseIndices: [Int]

    var orderedHoles: [CourseHole] {
        selectedSubCourseIndices.flatMap { index in
            course.subCourses[index].holes
        }
    }
}
