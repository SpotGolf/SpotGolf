import Foundation
import Observation
import os
import SensorSources

/// The watch's sensors and microphone, in one place. Each input runs while something
/// subscribes to it, and the subscribers' handlers get every batch on the sensor's own thread.
/// The inputs come from `SensorSet`: live on a watch, mocks on a simulator.
///
/// Every input is watched: one that errors, goes quiet for `RestartWatchdog.interval`, or sends
/// only data that is not real (`SensorHealth`) for that long, is started again from scratch,
/// so a round and a Putt Lab capture recover from a stall the same way. An input restarted
/// `RestartWatchdog.stallRestarts` times in a row with no real data is stalled, and `onStalled`
/// is called: for a batched sensor the workout probably needs a new session, which only
/// `WorkoutManager` can give it.
///
/// The batched sensors deliver only during a workout, so subscribers start them once the
/// workout runs and stop them when it ends; the watchdog restarts them in between.
@MainActor
@Observable
final class SensorInputs {
    enum Input: String, CaseIterable {
        /// 800 Hz, about one batch a second.
        case accelerometer
        /// 200 Hz rotation rate, user acceleration, gravity and attitude, about one batch a second.
        case deviceMotion
        /// 48 kHz mono buffers of 4096 frames.
        case microphone
    }

    typealias AccelerometerHandler = @Sendable ([AccelerometerSample]) -> Void
    typealias DeviceMotionHandler = @Sendable ([DeviceMotionSample]) -> Void
    /// One buffer at a time.
    typealias MicrophoneHandler = @Sendable (AudioSample) -> Void

    /// Ends the subscription; the input stops when no one else has one.
    final class Subscription {
        let input: Input
        fileprivate let id = UUID()
        private weak var inputs: SensorInputs?

        fileprivate init(_ input: Input, inputs: SensorInputs) {
            self.input = input
            self.inputs = inputs
        }

        @MainActor
        func cancel() {
            inputs?.remove(self)
            inputs = nil
        }
    }

    /// Taps on the app's own buttons, for the detectors to ignore.
    let taps = TapGuard()

    /// A swing is 17 to 22 g, so a reading over this means the accelerometer is alive.
    nonisolated static let highGThreshold: Double = 10

    /// The last accelerometer reading over `highGThreshold` since launch, for the screen.
    private(set) var lastHighG: HighGReading?

    /// Inputs that could not be started, with why, for the screen.
    private(set) var problems: [Input: String] = [:]

    /// Called on the main actor when an input has stalled: restarted `RestartWatchdog.stallRestarts`
    /// times in a row with no data. The microphone has been restarted again already.
    @ObservationIgnored var onStalled: ((Input) -> Void)?

    /// Called on the main actor with each event worth keeping in the round's stream.
    @ObservationIgnored var onEvent: ((StreamEvent) -> Void)?

    /// Called on the main actor with each tap on the app's buttons and each haptic, for Putt
    /// Lab's events: "tap" with no value, or "haptic" with the `WKHapticType` raw value.
    @ObservationIgnored var onGuarded: ((_ event: String, _ value: Double) -> Void)?

    /// After the mic refuses to start, the next try waits this long: usually permission is missing.
    static let microphoneRetryDelay: TimeInterval = 60

    @ObservationIgnored private let sources: SensorSet
    @ObservationIgnored private let accelerometer = Subscribers<[AccelerometerSample]>()
    @ObservationIgnored private let motion = Subscribers<[DeviceMotionSample]>()
    @ObservationIgnored private let audio = Subscribers<AudioSample>()
    /// When each input last sent real data, and any data, since it last started. Set on the sensors' threads.
    @ObservationIgnored private let lastReal: [Input: DataClock] =
        Dictionary(uniqueKeysWithValues: Input.allCases.map { ($0, DataClock()) })
    @ObservationIgnored private let lastAny: [Input: DataClock] =
        Dictionary(uniqueKeysWithValues: Input.allCases.map { ($0, DataClock()) })
    @ObservationIgnored private var running: Set<Input> = []
    @ObservationIgnored private var watchdogs: [Input: RestartWatchdog] = [:]
    @ObservationIgnored private var microphoneRetryAfter: Date?
    @ObservationIgnored private var timer: Timer?

    init(sources: SensorSet = .make()) {
        self.sources = sources
    }

    /// Whether the input is running and has sent real data since it last started.
    func isSendingRealData(_ input: Input) -> Bool {
        running.contains(input) && lastReal[input]?.date != nil
    }

    /// Whether the input is running and has sent any data, real or not, since it last started.
    func hasSentData(_ input: Input) -> Bool {
        running.contains(input) && lastAny[input]?.date != nil
    }

    /// A tap on one of the app's buttons: readings around it are ignored.
    func tapped() {
        taps.tapped()
        onGuarded?("tap", 0)
    }

    /// The last reading over `highGThreshold` in a batch of (uptime, magnitude in g), or nil.
    /// Called on the sensor's thread, so nonisolated: a main-actor method called there traps.
    nonisolated static func lastHighG(in readings: [(uptime: Double, magnitude: Double)]) -> HighGReading? {
        readings.last { $0.magnitude > highGThreshold }
            .map { HighGReading(date: Uptime.date(at: $0.uptime), magnitude: $0.magnitude) }
    }

    /// Stops every running input and starts it again from scratch, at the user's request.
    /// The watchdogs start over, and a microphone waiting out a refusal is tried right away.
    func restartAll(reason: String) {
        microphoneRetryAfter = nil
        for input in running {
            watchdogs[input] = RestartWatchdog(startedAt: Date(), checksData: true)
            restart(input, reason: reason)
        }
    }

    // MARK: - Subscribing

    func subscribeAccelerometer(_ handler: @escaping AccelerometerHandler) -> Subscription {
        let subscription = Subscription(.accelerometer, inputs: self)
        accelerometer.add(subscription.id, handler)
        startIfNeeded(.accelerometer)
        return subscription
    }

    func subscribeDeviceMotion(_ handler: @escaping DeviceMotionHandler) -> Subscription {
        let subscription = Subscription(.deviceMotion, inputs: self)
        motion.add(subscription.id, handler)
        startIfNeeded(.deviceMotion)
        return subscription
    }

    func subscribeMicrophone(_ handler: @escaping MicrophoneHandler) -> Subscription {
        let subscription = Subscription(.microphone, inputs: self)
        audio.add(subscription.id, handler)
        startIfNeeded(.microphone)
        return subscription
    }

    private func remove(_ subscription: Subscription) {
        let left: Int
        switch subscription.input {
        case .accelerometer: left = accelerometer.remove(subscription.id)
        case .deviceMotion: left = motion.remove(subscription.id)
        case .microphone: left = audio.remove(subscription.id)
        }
        if left == 0 {
            stop(subscription.input)
        }
    }

    // MARK: - Running

    private func startIfNeeded(_ input: Input) {
        guard !running.contains(input) else { return }
        running.insert(input)
        watchdogs[input] = RestartWatchdog(startedAt: Date(), checksData: true)
        start(input)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: RestartWatchdog.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.check() }
            }
        }
    }

    private func isActive(_ input: Input) -> Bool {
        switch input {
        case .accelerometer: sources.accelerometer.isActive
        case .deviceMotion: sources.deviceMotion.isActive
        case .microphone: sources.microphone.isActive
        }
    }

    private func start(_ input: Input) {
        watchdogs[input]?.started(at: Date())
        lastReal[input]?.clear()
        lastAny[input]?.clear()
        if input == .microphone, MicrophonePermission.state != .granted {
            problems[input] = String(localized: "No microphone permission")
            microphoneRetryAfter = Date().addingTimeInterval(Self.microphoneRetryDelay)
            Log.sensors.error("Microphone not started: permission \(String(describing: MicrophonePermission.state))")
            report(.microphoneError, value: 1)
            return
        }
        // The sources call these on their own threads, so @Sendable: a plain closure made here
        // would count as main-actor code, and Swift 6 traps when it runs anywhere else
        let clock = lastReal[input]!
        let anyClock = lastAny[input]!
        let onError: @Sendable (Error) -> Void = { [weak self] error in
            let code = (error as NSError).code
            Log.sensors.error("\(input.rawValue) error: \(String(describing: error))")
            Task { @MainActor in self?.failed(input, code: code) }
        }
        do {
            switch input {
            case .accelerometer:
                let subscribers = accelerometer
                try sources.accelerometer.start(onSamples: { @Sendable [weak self] batch in
                    subscribers.send(batch)
                    _ = anyClock.mark()
                    let highG = Self.lastHighG(in: batch.map { ($0.timestamp, $0.acceleration.magnitude) })
                    let first = SensorHealth.isReal(batch) ? clock.mark() : false
                    guard highG != nil || first else { return }
                    let count = batch.count
                    Task { @MainActor in
                        if let highG { self?.lastHighG = highG }
                        if first { self?.firstRealData(input, count: count) }
                    }
                }, onError: onError)
            case .deviceMotion:
                let subscribers = motion
                try sources.deviceMotion.start(onSamples: { @Sendable [weak self] batch in
                    subscribers.send(batch)
                    _ = anyClock.mark()
                    guard SensorHealth.isReal(batch), clock.mark() else { return }
                    let count = batch.count
                    Task { @MainActor in self?.firstRealData(input, count: count) }
                }, onError: onError)
            case .microphone:
                let subscribers = audio
                try sources.microphone.start(onSamples: { @Sendable [weak self] batch in
                    for buffer in batch {
                        subscribers.send(buffer)
                    }
                    _ = anyClock.mark()
                    guard SensorHealth.isReal(batch), clock.mark() else { return }
                    let count = batch.reduce(0) { $0 + $1.samples.count }
                    Task { @MainActor in self?.firstRealData(input, count: count) }
                }, onError: onError)
            }
        } catch SensorSourceError.unsupported {
            problems[input] = input == .accelerometer ? String(localized: "No accelerometer") : String(localized: "No device motion")
            Log.sensors.error("Batched \(input.rawValue) not supported on this watch")
            report(input == .accelerometer ? .accelerometerUnsupported : .deviceMotionUnsupported)
            return
        } catch {
            problems[input] = Self.failedProblem(input)
            if input == .microphone {
                microphoneRetryAfter = Date().addingTimeInterval(Self.microphoneRetryDelay)
                report(.microphoneError, value: 2)
            } else {
                report(Self.errorCode(input), value: Float((error as NSError).code))
            }
            Log.sensors.error("\(input.rawValue) did not start: \(String(describing: error))")
            return
        }
        problems[input] = nil
        if input == .microphone {
            report(.microphoneStarted)
        }
        Log.sensors.notice("\(input.rawValue) on")
    }

    private static func failedProblem(_ input: Input) -> String {
        switch input {
        case .accelerometer: String(localized: "Accelerometer failed")
        case .deviceMotion: String(localized: "Device motion failed")
        case .microphone: String(localized: "Microphone failed")
        }
    }

    private func stopSource(_ input: Input) {
        switch input {
        case .accelerometer: sources.accelerometer.stop()
        case .deviceMotion: sources.deviceMotion.stop()
        case .microphone: sources.microphone.stop()
        }
    }

    private func stop(_ input: Input) {
        guard running.contains(input) else { return }
        running.remove(input)
        watchdogs[input] = nil
        lastReal[input]?.clear()
        lastAny[input]?.clear()
        problems[input] = nil
        stopSource(input)
        Log.sensors.notice("\(input.rawValue) off")
        if running.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Stops the input and starts it again from scratch. Reports a stall once the watchdog has
    /// seen enough restarts with no real data between them.
    private func restart(_ input: Input, reason: String) {
        Log.sensors.error("\(input.rawValue) \(reason); restarting")
        stopSource(input)
        start(input)
        guard let watchdog = watchdogs[input] else { return }
        let restarts = Float(watchdog.restartsWithoutData)
        report(Self.restartCode(input), value: restarts)
        if watchdog.isStalled {
            watchdogs[input]?.stallReported()
            Log.sensors.error("\(input.rawValue) stalled: \(Int(restarts)) restarts with no data")
            report(Self.stalledCode(input), value: restarts)
            onStalled?(input)
        }
    }

    // MARK: - Watching

    private func firstRealData(_ input: Input, count: Int) {
        guard running.contains(input) else { return }
        Log.sensors.notice("First \(input.rawValue) batch: \(count) readings")
        if input != .microphone {
            report(Self.firstBatchCode(input), value: Float(count))
        }
    }

    /// An error may have ended updates. A start that keeps failing is left to `check`.
    private func failed(_ input: Input, code: Int) {
        guard running.contains(input) else { return }
        report(Self.errorCode(input), value: Float(code))
        guard watchdogs[input]?.shouldRestartAfterError(at: Date()) == true else { return }
        restart(input, reason: "stopped on an error")
    }

    /// Every `RestartWatchdog.interval`: an input that is not active, or has sent no real data
    /// for that long, is started again. A microphone that refused to start waits out
    /// `microphoneRetryDelay` first.
    private func check() {
        let now = Date()
        for input in running {
            if let last = lastReal[input]?.date {
                watchdogs[input]?.dataReceived(at: last)
            }
            let active = isActive(input)
            if input == .microphone, !active, now < microphoneRetryAfter ?? .distantPast { continue }
            guard watchdogs[input]?.shouldRestart(at: now, isActive: active) == true else { continue }
            restart(input, reason: active ? "sent no real data for \(Int(RestartWatchdog.interval)) s" : "not running")
        }
    }

    // MARK: - Events

    private func report(_ code: StreamEvent.Code, value: Float = 0) {
        onEvent?(StreamEvent(code: code, value: value))
    }

    private static func firstBatchCode(_ input: Input) -> StreamEvent.Code {
        switch input {
        case .accelerometer: .accelerometerFirstBatch
        case .deviceMotion: .deviceMotionFirstBatch
        case .microphone: .microphoneStarted
        }
    }

    private static func errorCode(_ input: Input) -> StreamEvent.Code {
        switch input {
        case .accelerometer: .accelerometerError
        case .deviceMotion: .deviceMotionError
        case .microphone: .microphoneError
        }
    }

    private static func restartCode(_ input: Input) -> StreamEvent.Code {
        switch input {
        case .accelerometer: .accelerometerRestart
        case .deviceMotion: .deviceMotionRestart
        case .microphone: .microphoneRestart
        }
    }

    private static func stalledCode(_ input: Input) -> StreamEvent.Code {
        switch input {
        case .accelerometer: .accelerometerStalled
        case .deviceMotion: .deviceMotionStalled
        case .microphone: .microphoneStalled
        }
    }
}

/// An accelerometer reading over `SensorInputs.highGThreshold`. A top-level type, so it is
/// not main-actor isolated and can be made on the sensor's thread.
struct HighGReading: Equatable, Sendable {
    let date: Date
    let magnitude: Double
}

/// When an input last sent data: marked on the sensor's thread, read on the main actor.
private final class DataClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date?

    var date: Date? {
        lock.withLock { value }
    }

    /// Marks now and returns true when this is the first real data since `clear`.
    func mark() -> Bool {
        lock.withLock {
            let first = value == nil
            value = Date()
            return first
        }
    }

    func clear() {
        lock.withLock { value = nil }
    }
}

/// Handlers keyed by subscription, added and removed on the main actor and called on a
/// sensor's thread.
private final class Subscribers<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [UUID: (Value) -> Void] = [:]

    func add(_ id: UUID, _ handler: @escaping (Value) -> Void) {
        lock.lock()
        handlers[id] = handler
        lock.unlock()
    }

    /// Removes the handler and returns how many are left.
    func remove(_ id: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: id)
        return handlers.count
    }

    func send(_ value: Value) {
        lock.lock()
        let current = Array(handlers.values)
        lock.unlock()
        for handler in current {
            handler(value)
        }
    }
}
