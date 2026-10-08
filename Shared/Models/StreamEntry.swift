import Foundation
import SwiftData

/// One record of a round's stream from the watch, saved with SwiftData. `index` is the
/// record's position in the stream, which both devices agree on.
@Model
final class StreamEntry {
    var roundID: UUID
    var index: Int
    /// The record as `StreamRecord.record` encodes it, the same bytes the watch sends.
    var record: Data

    init(roundID: UUID, index: Int, record: Data) {
        self.roundID = roundID
        self.index = index
        self.record = record
    }
}
