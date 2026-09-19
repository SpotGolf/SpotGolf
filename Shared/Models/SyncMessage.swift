import Foundation
import CourseData

enum SyncMessage {
    case startRound(UUID, Date)
    case endRound(UUID)
    case addMark(BallMark, Int, UUID) // mark, holeIndex, roundID
    case setCourse(CourseSelection, UUID)
    case setMarkType(UUID, BallMarkType, UUID) // markID, type, roundID
    case addGuess(MissedMarkGuess, UUID) // guess, roundID
    case removeGuess(UUID, UUID) // guessID, roundID
    case clearGuesses(UUID, Int) // roundID, holeIndex
    case updateSettings(AppSettings)
}
