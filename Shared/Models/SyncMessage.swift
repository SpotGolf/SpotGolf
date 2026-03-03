import Foundation

enum SyncMessage {
    case startRound(UUID, Date)
    case endRound(UUID)
    case addMark(BallMark, UUID)
    case nextHole(UUID)
    case previousHole(UUID)
}
