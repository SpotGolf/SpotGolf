import Foundation

/// How the app was launched, read once from the launch arguments. UI tests pass these to run
/// without a paired device, iCloud, or permissions, and to set up rounds.
struct LaunchOptions {
    /// `--ui-testing`: running under UI tests on a simulator.
    var isUITesting = false
    /// `--keep-rounds` (watch): keeps saved rounds, for tests that relaunch mid-round.
    var keepsRounds = false
    /// `--start-round` (watch): starts a round on the watch alone.
    var startsRound = false

    init(isUITesting: Bool = false, keepsRounds: Bool = false, startsRound: Bool = false) {
        self.isUITesting = isUITesting
        self.keepsRounds = keepsRounds
        self.startsRound = startsRound
    }

    init(arguments: [String]) {
        isUITesting = arguments.contains("--ui-testing")
        keepsRounds = arguments.contains("--keep-rounds")
        startsRound = arguments.contains("--start-round")
    }

    static let current = LaunchOptions(arguments: CommandLine.arguments)
}
