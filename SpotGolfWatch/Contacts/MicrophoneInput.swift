import AVFAudio
import Foundation
import os

/// The watch's microphone through `AVAudioEngine`: hands each buffer to `onBuffer` with the
/// host time of its first sample, and can also write a WAV file for a Putt Lab capture. Mono
/// 16-bit PCM at the mic's own rate. One instance per start.
@MainActor
final class MicrophoneInput {
    typealias BufferHandler = (_ samples: [Float], _ hostSeconds: Double, _ sampleRate: Double) -> Void

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private let frames = FrameCounter()
    private let onBuffer: BufferHandler?

    /// Frames received so far.
    var frameCount: Int { frames.count }

    /// Set once the first buffer arrives.
    private(set) var audio: PuttCapture.Audio?

    /// `onBuffer` runs on the audio thread with every buffer.
    init(onBuffer: BufferHandler? = nil) {
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

    /// Starts the mic, writing to `url` when given. `captureStartUptime` is the zero of the
    /// capture time in `audio`, on the uptime clock.
    func start(to url: URL?, captureStartUptime: Double) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
        } catch {
            Log.contacts.error("Measurement mode refused; using the default mode: \(String(describing: error), privacy: .public)")
            try session.setCategory(.record)
        }
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneError.noInput
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try url.map { try AVAudioFile(forWriting: $0, settings: settings,
                                                 commonFormat: format.commonFormat, interleaved: format.isInterleaved) }
        self.file = file
        let frames = self.frames
        let onBuffer = self.onBuffer.map(BufferCallback.init)
        let onFirstBuffer = FirstBuffer { [weak self] audio in
            Task { @MainActor in self?.audio = audio }
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in
            let hostSeconds = AVAudioTime.seconds(forHostTime: when.hostTime)
            if frames.count == 0 {
                onFirstBuffer.handler(PuttCapture.Audio(sampleRate: format.sampleRate,
                                                        channels: Int(format.channelCount),
                                                        startTime: hostSeconds - captureStartUptime,
                                                        startHostTime: hostSeconds,
                                                        startUptime: ProcessInfo.processInfo.systemUptime))
            }
            if let file {
                do {
                    try file.write(from: buffer)
                } catch {
                    Log.contacts.error("Audio write failed: \(String(describing: error), privacy: .public)")
                }
            }
            if let onBuffer, let channel = buffer.floatChannelData?[0] {
                onBuffer.handler(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), hostSeconds, format.sampleRate)
            }
            frames.add(Int(buffer.frameLength))
        }
        engine.prepare()
        try engine.start()
        Log.contacts.notice("Microphone started: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) channel(s), file \(url != nil, privacy: .public)")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            Log.contacts.error("Could not deactivate the audio session: \(String(describing: error), privacy: .public)")
        }
        Log.contacts.notice("Microphone stopped: \(self.frames.count, privacy: .public) frames")
    }
}

enum MicrophoneError: Error {
    case noInput
}

/// Frames received, counted on the audio thread and read on the main actor.
private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func add(_ frames: Int) {
        lock.lock()
        value += frames
        lock.unlock()
    }
}

private struct FirstBuffer: @unchecked Sendable {
    let handler: (PuttCapture.Audio) -> Void
    init(_ handler: @escaping (PuttCapture.Audio) -> Void) { self.handler = handler }
}

private struct BufferCallback: @unchecked Sendable {
    let handler: MicrophoneInput.BufferHandler
    init(_ handler: @escaping MicrophoneInput.BufferHandler) { self.handler = handler }
}
