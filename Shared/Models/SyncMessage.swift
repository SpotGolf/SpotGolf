import Foundation

enum SyncMessage {
    case startRound(UUID, Date)
    case endRound(UUID)
    case addMark(BallMark, Int, UUID) // mark, holeIndex, roundID
    case setCourse(CourseSelection, UUID)
    case setMarkType(UUID, BallMarkType, UUID) // markID, type, roundID
}
