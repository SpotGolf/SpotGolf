import Foundation

/// One drill of a Putt Data Sharing session: 5 tasks with the same setup. See
/// `plans/2026-10-27-putt-data-sharing.md`, section 2.3.
struct Drill: Equatable {
    /// Names the drill in `drill.json`, whatever the wording on screen.
    let key: String
    /// The paused screen's name for it: "Next: 3 foot putts".
    let name: String
    /// How to set it up, on the paused screen.
    let setup: String
    /// One task, on the task screen.
    let task: String
    /// The drill uses balls, so they are collected after it.
    let usesBalls: Bool

    static let tasks = 5

    /// The drills, in order. Tap-ins leave the balls in the cup for the drill after them, and
    /// the drills with no ball need no collecting.
    static let all: [Drill] = [
        Drill(key: "putt3ft", name: String(localized: "3 foot putts"),
              setup: String(localized: "Put 5 balls 3 feet from a hole."),
              task: String(localized: "Hit a 3 foot putt, then tap Done."), usesBalls: true),
        Drill(key: "practiceThenPutt10ft", name: String(localized: "10 foot putts with a practice stroke"),
              setup: String(localized: "Put 5 balls 10 feet from a hole."),
              task: String(localized: "Take one practice stroke, hit a 10 foot putt, then tap Done."), usesBalls: true),
        Drill(key: "putt30ft", name: String(localized: "30 foot putts"),
              setup: String(localized: "Put 5 balls 30 feet from a hole."),
              task: String(localized: "Hit a 30 foot putt, then tap Done."), usesBalls: true),
        Drill(key: "tapIn1ft", name: String(localized: "Tap-ins"),
              setup: String(localized: "Put 5 balls 1 foot from a hole."),
              task: String(localized: "Tap in a 1 foot putt, then tap Done."), usesBalls: true),
        Drill(key: "pickFromCup", name: String(localized: "Picking balls out of the cup"),
              setup: String(localized: "Leave the balls in the cup."),
              task: String(localized: "Pick a ball out of the cup, then tap Done."), usesBalls: false),
        Drill(key: "practiceAir", name: String(localized: "Practice strokes above the grass"),
              setup: String(localized: "No balls needed."),
              task: String(localized: "Take a practice stroke with the putter above the grass, then tap Done."), usesBalls: false),
        Drill(key: "practiceBrush", name: String(localized: "Practice strokes that brush the grass"),
              setup: String(localized: "No balls needed."),
              task: String(localized: "Take a practice stroke that brushes the grass, then tap Done."), usesBalls: false),
        Drill(key: "pullBall", name: String(localized: "Pulling a ball with the putter"),
              setup: String(localized: "Put a ball 2 feet from you."),
              task: String(localized: "Pull the ball toward you with the putter head, then tap Done."), usesBalls: true)
    ]
}

/// Where a session is: paused before a drill, on a task, or finished. Pure, so the flow is
/// tested without the sensors. Times are seconds from the session's start.
struct DrillSession: Equatable {
    enum Step: Equatable {
        /// Waiting for Ready before drill `next`, an index into `drills`.
        case paused(next: Int)
        /// Task `task` (from 0) of drill `drill`.
        case task(drill: Int, task: Int)
        case finished
    }

    /// What `drill.json` holds.
    struct Record: Codable, Equatable {
        static let file = "drill.json"
        static let version = 1

        struct DrillRecord: Codable, Equatable {
            let number: Int
            let key: String
            /// When Ready was tapped, or nil when the drill never started.
            var ready: Double?
            var skipped: Bool
        }

        struct TaskRecord: Codable, Equatable {
            let drill: Int
            let task: Int
            let key: String
            /// When the task showed.
            let start: Double
            /// When Done was tapped, or nil when the drill was skipped or the session stopped.
            var done: Double?
        }

        var version = Record.version
        var drills: [DrillRecord]
        var tasks: [TaskRecord] = []

        /// Drills with every task done.
        var drillsFinished: Int {
            drills.filter { drill in
                !drill.skipped && tasks.filter { $0.drill == drill.number && $0.done != nil }.count == Drill.tasks
            }.count
        }
    }

    let drills: [Drill]
    private(set) var step = Step.paused(next: 0)
    private(set) var record: Record

    init(drills: [Drill] = Drill.all) {
        self.drills = drills
        record = Record(drills: drills.enumerated().map { index, drill in
            Record.DrillRecord(number: index + 1, key: drill.key, ready: nil, skipped: false)
        })
    }

    /// The drill the paused screen leads to, or the task screen is in.
    var currentDrill: Drill? {
        switch step {
        case .paused(let next): drills.indices.contains(next) ? drills[next] : nil
        case .task(let drill, _): drills[drill]
        case .finished: nil
        }
    }

    /// The paused screen comes after a drill that used balls.
    var collectsBalls: Bool {
        guard case .paused(let next) = step, next > 0 else { return false }
        return drills[next - 1].usesBalls && !record.drills[next - 1].skipped
    }

    /// Drills with every task done.
    var drillsFinished: Int { record.drillsFinished }

    /// The number, from 1, of the drill the paused screen leads to or the task is in.
    var drillNumber: Int? {
        switch step {
        case .paused(let next): drills.indices.contains(next) ? next + 1 : nil
        case .task(let drill, _): drill + 1
        case .finished: nil
        }
    }

    /// Ready on the paused screen: the drill's first task shows.
    mutating func ready(at time: Double) {
        guard case .paused(let next) = step, drills.indices.contains(next) else { return }
        record.drills[next].ready = time
        showTask(drill: next, task: 0, at: time)
    }

    /// Done on the task screen: the next task shows at once, or the paused screen after the
    /// drill's last.
    mutating func done(at time: Double) {
        guard case .task(let drill, let task) = step else { return }
        record.tasks[record.tasks.count - 1].done = time
        if task + 1 < Drill.tasks {
            showTask(drill: drill, task: task + 1, at: time)
        } else {
            pause(before: drill + 1)
        }
    }

    /// Skip drill: on to the paused screen for the drill after the current one.
    mutating func skipDrill() {
        switch step {
        case .paused(let next) where drills.indices.contains(next):
            record.drills[next].skipped = true
            pause(before: next + 1)
        case .task(let drill, _):
            record.drills[drill].skipped = true
            pause(before: drill + 1)
        default:
            return
        }
    }

    /// Stop: the session ends with the drills done so far.
    mutating func stop() {
        step = .finished
    }

    private mutating func showTask(drill: Int, task: Int, at time: Double) {
        step = .task(drill: drill, task: task)
        record.tasks.append(Record.TaskRecord(drill: drill + 1, task: task + 1, key: drills[drill].key, start: time, done: nil))
    }

    private mutating func pause(before next: Int) {
        step = next < drills.count ? .paused(next: next) : .finished
    }
}
