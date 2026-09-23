import Foundation
import CourseDataSwift

enum SyncMessage {
    case startRound(UUID, Date, CourseSelection)
    case endRound(UUID)
    case addMark(BallMark, Int, UUID) // mark, holeIndex, roundID
    case setHole(Int, UUID, Date) // holeIndex, roundID, when the hole was chosen
    case setMarkType(UUID, BallMarkType, UUID) // markID, type, roundID
    case addGuess(MissedMarkGuess, UUID) // guess, roundID
    case removeGuess(UUID, UUID) // guessID, roundID
    case updateSettings(AppSettings)
}
