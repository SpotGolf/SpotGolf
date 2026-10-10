import AVFAudio
import CoreMotion
import Foundation
import Observation
import os

/// The watch's sensors and microphone, in one place. Each input runs while something
/// subscribes to it, and the subscribers' handlers get every batch on the sensor's own thread.
/// Every input is watched: one that errors, or goes quiet for `RestartWatchdog.interval`, is
/// started again on a fresh manager, so a round and a Putt Lab capture recover from a stall
/// the same way. An input restarted `RestartWatchdog.stallRestarts` times in a row with no data
/// is stalled, and `onStalled` is called: for a batched sensor the workout probably needs a new
/// session, which only `WorkoutManager` can give it.
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

    typealias AccelerometerHandler = @Sendable ([CMAccelerometerData]) -> Void
    typealias DeviceMotionHandler = @Sendable ([CMDeviceMotion]) -> Void
    typealias MicrophoneHandler = MicrophoneInput.BufferHandler

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

    /// Inputs that could not be started, with why, for the screen.
    private(set) var problems: [Input: String] = [:]

    /// Called on the main actor when an input has stalled: restarted `RestartWatchdog.stallRestarts`
    /// times in a row with no data. The microphone has been restarted again already.
    @ObservationIgnored var onStalled: ((Input) -> Void)?

    /// Called on the main actor with each event worth keeping in the round's stream.
    @ObservationIgnored var onEvent: ((StreamEvent) -> Void)?

    /// After the mic refuses to start, the next try waits this long: usually permission is missing.
    static let microphoneRetryDelay: TimeInterval = 60

    // One manager per batched sensor, replaced on every restart in case the old one is wedged
    @ObservationIgnored private var accelerometerManager = CMBatchedSensorManager()
    @ObservationIgnored private var motionManager = CMBatchedSensorManager()
    @ObservationIgnored private let microphone: MicrophoneInput
    @ObservationIgnored private let accelerometer = Subscribers<[CMAccelerometerData]>()
    @ObservationIgnored private let motion = Subscribers<[CMDeviceMotion]>()
    @ObservationIgnored private let audio: Subscribers<(AVAudioPCMBuffer, Double)>
    @ObservationIgnored private var running: Set<Input> = []
    @ObservationIgnored private var watchdogs: [Input: RestartWatchdog] = [:]
    @ObservationIgnored private var lastData: [Input: Date] = [:]
    @ObservationIgnored private var microphoneRetryAfter: Date?
    @ObservationIgnored private var timer: Timer?

    init() {
        let audio = Subscribers<(AVAudioPCMBuffer, Double)>()
        self.audio = audio
        microphone = MicrophoneInput { buffer, hostSeconds in audio.send((buffer, hostSeconds)) }
    }

    /// A tap on one of the app's buttons: readings around it are ignored.
    func tapped() {
        taps.tapped()
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
        audio.add(subscription.id) { handler($0.0, $0.1) }
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
        lastData[input] = nil
        start(input)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: RestartWatchdog.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.check() }
            }
        }
    }

    private func start(_ input: Input) {
        watchdogs[input]?.started(at: Date())
        switch input {
        case .accelerometer:
            guard CMBatchedSensorManager.isAccelerometerSupported else {
                problems[input] = String(localized: "No accelerometer")
                Log.sensors.error("Batched accelerometer not supported on this watch")
                report(.accelerometerUnsupported)
                return
            }
            problems[input] = nil
            let manager = CMBatchedSensorManager()
            accelerometerManager = manager
            // CoreMotion calls this on its own queue, so @Sendable: a plain closure made here
            // would count as main-actor code, and Swift 6 traps when it runs anywhere else
            manager.startAccelerometerUpdates { @Sendable [weak self, accelerometer] batch, error in
                if let error {
                    let code = (error as NSError).code
                    Log.sensors.error("Accelerometer error: \(String(describing: error))")
                    Task { @MainActor in self?.failed(.accelerometer, code: code) }
                }
                guard let batch else { return }
                accelerometer.send(batch)
                let count = batch.count
                Task { @MainActor in self?.received(.accelerometer, count: count) }
            }
        case .deviceMotion:
            guard CMBatchedSensorManager.isDeviceMotionSupported else {
                problems[input] = String(localized: "No device motion")
                Log.sensors.error("Batched device motion not supported on this watch")
                report(.deviceMotionUnsupported)
                return
            }
            problems[input] = nil
            let manager = CMBatchedSensorManager()
            motionManager = manager
            manager.startDeviceMotionUpdates { @Sendable [weak self, motion] batch, error in
                if let error {
                    let code = (error as NSError).code
                    Log.sensors.error("Device motion error: \(String(describing: error))")
                    Task { @MainActor in self?.failed(.deviceMotion, code: code) }
                }
                guard let batch else { return }
                motion.send(batch)
                let count = batch.count
                Task { @MainActor in self?.received(.deviceMotion, count: count) }
            }
        case .microphone:
            guard MicrophoneInput.permission == .granted else {
                problems[input] = String(localized: "No microphone permission")
                microphoneRetryAfter = Date().addingTimeInterval(Self.microphoneRetryDelay)
                Log.sensors.error("Microphone not started: permission \(String(describing: MicrophoneInput.permission))")
                report(.microphoneError, value: 1)
                return
            }
            do {
                try microphone.start()
                problems[input] = nil
                report(.microphoneStarted)
            } catch {
                problems[input] = String(localized: "Microphone failed")
                microphoneRetryAfter = Date().addingTimeInterval(Self.microphoneRetryDelay)
                Log.sensors.error("Microphone did not start: \(String(describing: error))")
                report(.microphoneError, value: 2)
                return
            }
        }
        Log.sensors.notice("\(input.rawValue) on")
    }

    private func stop(_ input: Input) {
        guard running.contains(input) else { return }
        running.remove(input)
        watchdogs[input] = nil
        lastData[input] = nil
        problems[input] = nil
        switch input {
        case .accelerometer: accelerometerManager.stopAccelerometerUpdates()
        case .deviceMotion: motionManager.stopDeviceMotionUpdates()
        case .microphone: microphone.stop()
        }
        Log.sensors.notice("\(input.rawValue) off")
        if running.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Stops the input and starts it again on a fresh manager. Reports a stall once the
    /// watchdog has seen enough restarts with no data between them.
    private func restart(_ input: Input, reason: String) {
        Log.sensors.error("\(input.rawValue) \(reason); restarting")
        switch input {
        case .accelerometer: accelerometerManager.stopAccelerometerUpdates()
        case .deviceMotion: motionManager.stopDeviceMotionUpdates()
        case .microphone: microphone.stop()
        }
        lastData[input] = nil
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

    private func received(_ input: Input, count: Int) {
        let now = Date()
        if lastData[input] == nil {
            Log.sensors.notice("First \(input.rawValue) batch: \(count) readings")
            report(Self.firstBatchCode(input), value: Float(count))
        }
        lastData[input] = now
        watchdogs[input]?.dataReceived(at: now)
    }

    /// An error may have ended updates. A start that keeps failing is left to `check`.
    private func failed(_ input: Input, code: Int) {
        guard running.contains(input) else { return }
        report(Self.errorCode(input), value: Float(code))
        guard watchdogs[input]?.shouldRestartAfterError(at: Date()) == true else { return }
        restart(input, reason: "stopped on an error")
    }

    /// Every `RestartWatchdog.interval`: an input that is not active, or has sent nothing for
    /// that long, is started again.
    private func check() {
        let now = Date()
        for input in running {
            switch input {
            case .accelerometer:
                let active = accelerometerManager.isAccelerometerActive
                guard watchdogs[input]?.shouldRestart(at: now, isActive: active) == true else { continue }
                restart(input, reason: "quiet for \(Int(RestartWatchdog.interval)) s (active \(active))")
            case .deviceMotion:
                let active = motionManager.isDeviceMotionActive
                guard watchdogs[input]?.shouldRestart(at: now, isActive: active) == true else { continue }
                restart(input, reason: "quiet for \(Int(RestartWatchdog.interval)) s (active \(active))")
            case .microphone:
                if !microphone.isRunning {
                    guard now >= microphoneRetryAfter ?? .distantPast else { continue }
                    restart(input, reason: "not running")
                } else if let last = microphone.lastBufferAt {
                    guard now.timeIntervalSince(last) > RestartWatchdog.interval else { continue }
                    restart(input, reason: "quiet for \(Int(RestartWatchdog.interval)) s")
                } else if watchdogs[input]?.shouldRestart(at: now, isActive: true) == true {
                    restart(input, reason: "no buffers since it started")
                }
            }
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
