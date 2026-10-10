import AVFAudio
import Foundation
import os

/// Writes a capture's microphone buffers to a WAV file, mono 16-bit PCM at the mic's own
/// rate, and works out the capture time of the first sample from the first buffer's host
/// time. Used on the audio thread; read on the main actor once closed.
final class CaptureAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL?
    private let captureStartUptime: Double
    private var file: AVAudioFile?
    private var frames = 0
    private var info: PuttCapture.Audio?
    private var closed = false

    /// With no `url` nothing is written: the buffers are only counted, as in a battery test.
    init(url: URL?, captureStartUptime: Double) {
        self.url = url
        self.captureStartUptime = captureStartUptime
    }

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    /// Set once the first buffer has arrived.
    var audio: PuttCapture.Audio? {
        lock.lock()
        defer { lock.unlock() }
        return info
    }

    func write(_ buffer: AVAudioPCMBuffer, hostSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        if info == nil {
            info = PuttCapture.Audio(sampleRate: buffer.format.sampleRate, channels: Int(buffer.format.channelCount),
                                     startTime: hostSeconds - captureStartUptime, startHostTime: hostSeconds,
                                     startUptime: Uptime.now)
            if let url {
                do {
                    file = try AVAudioFile(forWriting: url, settings: Self.settings(for: buffer.format),
                                           commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
                } catch {
                    Log.puttLab.error("Could not create the audio file: \(String(describing: error))")
                }
            }
        }
        if let file {
            do {
                try file.write(from: buffer)
            } catch {
                Log.puttLab.error("Audio write failed: \(String(describing: error))")
            }
        }
        frames += Int(buffer.frameLength)
    }

    func close() {
        lock.lock()
        closed = true
        file = nil
        lock.unlock()
    }

    private static func settings(for format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
}
