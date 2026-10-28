import Foundation

/// Putt Data Sharing: players record putting drills on the watch and share them, so putt
/// detection can be checked against other players and putters. The types both apps use.
/// See `plans/2026-10-27-putt-data-sharing.md`.
enum PuttSharing {
    /// The consent the phone asks for. A higher version asks again.
    static let consentVersion = 1

    /// A session's archive is moved to the phone with these metadata keys.
    enum FileKey {
        static let sessionID = "sessionID"
        static let date = "date"
        static let drillsFinished = "drillsFinished"
        static let hasLocation = "hasLocation"
    }

    /// The player's putter, ball and game, asked once on the phone and sent with every session.
    struct Equipment: Codable, Equatable {
        enum Hand: String, Codable, CaseIterable {
            case right, left
        }
        enum PutterHead: String, Codable, CaseIterable {
            case blade, mallet
        }
        enum PutterFace: String, Codable, CaseIterable {
            case insert, milled
        }
        enum PutterLength: String, Codable, CaseIterable {
            case standard, armLock, long
        }
        enum Grip: String, Codable, CaseIterable {
            case standard, crossHanded, claw, other
        }
        enum Ball: String, Codable, CaseIterable {
            case soft, firm, unknown
        }
        enum Handicap: String, Codable, CaseIterable {
            case under10, from10To20, over20, none
        }

        var hand = Hand.right
        var putterHead = PutterHead.blade
        var putterFace = PutterFace.insert
        var putterLength = PutterLength.standard
        var grip = Grip.standard
        var ball = Ball.unknown
        var handicap = Handicap.none
    }

    /// The session's starting location, rounded to about 11 m.
    struct Location: Codable, Equatable {
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
        /// Seconds from the session's start.
        let t: Double

        /// Rounds to 4 decimal places: enough to see the green on a map, not the exact spot.
        static func rounded(_ value: Double) -> Double {
            (value * 10_000).rounded() / 10_000
        }
    }

    /// Why a session has no location.
    enum LocationStatus: String, Codable {
        case denied
        case noFix
    }

    /// `sharing.json` in a session: who shared it, with what, and where.
    struct Info: Codable, Equatable {
        static let file = "sharing.json"

        let sessionID: UUID
        let appVersion: String
        let watchModel: String
        let watchOSVersion: String
        let consentVersion: Int
        let sharerID: UUID
        let equipment: Equipment
        var location: Location?
        var locationStatus: LocationStatus?
        /// `audio.caf` or `audio.wav`: which audio file the archive holds.
        var audioFile: String?
    }
}

/// Phone → watch, queued: what the watch needs to run the drills. Nil fields mean not set yet:
/// a player who has not agreed has no consent version, and the watch does not offer the drills.
struct PhoneSettingsMessage: Codable, Equatable {
    let consentVersion: Int?
    let sharerID: UUID?
    let equipment: PuttSharing.Equipment?
}

/// Watch → phone, queued: a session finished and its archive is on its way, so the phone can
/// list it as on the watch until the file arrives.
struct PuttSessionNotice: Codable, Equatable {
    let sessionID: UUID
    let date: Date
    let drillsFinished: Int
    let size: Int64
    let hasLocation: Bool
}
