import AVFAudio
import Foundation
import os

/// The watch's microphone through `AVAudioEngine`: hands each buffer to `onBuffer` on the audio
/// thread with the host time of its first frame. Starts itself again after an audio
/// interruption or a configuration change, which otherwise leave the engine stopped for good.
/// `SensorInputs` owns the one instance; nothing else starts the mic.
@MainActor
final class MicrophoneInput {
    typealias BufferHandler = @Sendable (_ buffer: AVReadOnlyAudioPCMBuffer, _ hostSeconds: Double) -> Void

    private let engine = AVAudioEngine()
    private let onBuffer: BufferHandler
    private let lastBuffer = LastBuffer()
    private var sessionObservers: [NotificationCenter.ObservationToken] = []
    private var configurationObserver: NSObjectProtocol?

    private(set) var isRunning = false

    /// When the last buffer arrived, or nil before the first.
    var lastBufferAt: Date? { lastBuffer.date }

    init(onBuffer: @escaping BufferHandler) {
        self.onBuffer = onBuffer
    }

    nonisolated static var permission: PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .notAsked
        case .granted: .granted
        default: .denied
        }
    }

    static func requestPermission() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }

    /// The first channel of a buffer, in full-scale units.
    nonisolated static func samples(_ buffer: AVReadOnlyAudioPCMBuffer) -> [Float] {
        guard case .float(let channel) = buffer.channelData(0) else { return [] }
        return (0..<channel.count).map { channel[$0] }
    }

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
        } catch {
            Log.sensors.error("Measurement mode refused; using the default mode: \(String(describing: error))")
            try session.setCategory(.record)
        }
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneError.noInput
        }
        let onBuffer = self.onBuffer
        let lastBuffer = self.lastBuffer
        // The audio thread calls this, so @Sendable: a plain closure made here would count as
        // main-actor code, and Swift 6 traps when it runs anywhere else
        try input.installAudioTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, when in
            lastBuffer.mark()
            onBuffer(buffer, AVAudioTime.seconds(forHostTime: when.hostTime))
        }
        engine.prepare()
        try engine.start()
        isRunning = true
        lastBuffer.clear()
        observe()
        Log.sensors.notice("Microphone started: \(format.sampleRate) Hz, \(format.channelCount) channel(s)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let center = NotificationCenter.default
        for observer in sessionObservers {
            center.removeObserver(observer)
        }
        sessionObservers = []
        if let configurationObserver {
            center.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            Log.sensors.error("Could not deactivate the audio session: \(String(describing: error))")
        }
        Log.sensors.notice("Microphone stopped")
    }

    /// An interruption, or a changed input, stops the engine; it is started again with the
    /// input's current format once the interruption is over or the input has changed.
    private func observe() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        sessionObservers.append(center.addObserver(of: session, for: .didBecomeInactive) { message in
            // `stop()` deactivating the session is reported too; only the system's matters
            guard case .systemInterruption(let context) = message.deactivationResult else { return }
            Log.sensors.notice("Microphone interrupted: reason \(context.reason.rawValue)")
        })
        // Restarted whatever the recommendation: the mic records sensor data, not playback
        sessionObservers.append(center.addObserver(of: session, for: .resumptionRecommendation) { [weak self] _ in
            self?.restart(reason: "the interruption ended")
        })
        configurationObserver = center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.restart(reason: "the audio configuration changed") }
        }
    }

    /// Starts the engine again after it was stopped from outside; `stop()` then `start()`
    /// keeps the handler and the session.
    func restart(reason: String) {
        guard isRunning else { return }
        Log.sensors.notice("Microphone restarting: \(reason)")
        stop()
        do {
            try start()
        } catch {
            Log.sensors.error("Microphone did not restart: \(String(describing: error))")
        }
    }
}

enum MicrophoneError: Error {
    case noInput
}

/// When the last buffer arrived, set on the audio thread and read on the main actor.
private final class LastBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date?

    var date: Date? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func mark() {
        lock.lock()
        value = Date()
        lock.unlock()
    }

    func clear() {
        lock.lock()
        value = nil
        lock.unlock()
    }
}
