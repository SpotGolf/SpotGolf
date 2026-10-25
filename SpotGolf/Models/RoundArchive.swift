import Foundation
import CourseDataSwift

/// An ended round and its stream as saved in iCloud: JSON, gzipped, in the `Round` record's
/// asset. Kept apart from the SwiftData model so the stored format only changes on purpose.
/// See plans/2026-10-22-cloudkit-sync.md.
struct RoundArchive: Codable, Equatable {
    /// The version this build writes. Bump it for any change to the keys or what they hold.
    static let currentVersion = 1

    enum ArchiveError: Error, Equatable {
        /// Written by a newer version of the app.
        case newerVersion(Int)
    }

    var version: Int
    var id: UUID
    var date: Date
    var endedAt: Date?
    var changedAt: Date
    var holes: [RoundHole]
    var holeStarts: [Date?]
    var pins: [PinLocation?]
    var displayHole: DisplayHole
    var courseSelection: CourseSelection
    /// The round's 25-byte stream records, packed by `StreamEncoding`.
    var stream: Data

    /// `records` is the round's stream, as `StreamStore.data(for:from:maxBytes:)` gives it.
    init(round: Round, records: Data) {
        version = Self.currentVersion
        id = round.id
        date = round.date
        endedAt = round.endedAt
        changedAt = round.changedAt
        holes = round.holes
        holeStarts = round.holeStarts
        pins = round.pins
        displayHole = round.displayHole
        // Only the nines played and their features, as the watch gets: the course is most of a
        // short round's size, and an unplayed nine is half of it
        courseSelection = round.courseSelection.trimmed
        stream = StreamEncoding.encode(records)
    }

    func gzipped() throws -> Data {
        try JSONEncoder().encode(self).gzipCompressed()
    }

    /// Reads a gzipped archive. Throws `ArchiveError.newerVersion` for one this build can't read.
    static func read(gzipped data: Data) throws -> RoundArchive {
        let json = try data.gzipDecompressed()
        // The version alone first, so a newer format with other keys still reports its version
        let version = try JSONDecoder().decode(VersionOnly.self, from: json).version
        guard version <= currentVersion else { throw ArchiveError.newerVersion(version) }
        return try JSONDecoder().decode(RoundArchive.self, from: json)
    }

    private struct VersionOnly: Decodable {
        var version: Int
    }

    /// The 25-byte stream records.
    func records() throws -> Data {
        try StreamEncoding.decode(stream)
    }

    /// A new ended round made from the archive.
    func makeRound() -> Round {
        let round = Round(id: id, date: date, status: .ended, courseSelection: courseSelection)
        apply(to: round)
        return round
    }

    /// Makes `round` match the archive. Values that only matter while the watch records a round
    /// are set for an ended round the watch has finished with.
    func apply(to round: Round) {
        round.date = date
        round.status = .ended
        round.endedAt = endedAt
        round.resumedFromEnd = nil
        round.endConfirmed = true
        round.holes = holes
        round.holeStarts = holeStarts
        round.pins = pins
        round.displayHole = displayHole
        round.courseSelection = courseSelection
        round.changedAt = changedAt
    }
}
