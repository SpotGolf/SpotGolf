import AVFAudio
import Foundation
import os
import SensorSources

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

    /// Writes the buffer and returns the index of its first frame in the file, or nil once closed.
    @discardableResult
    func write(_ buffer: AudioSample) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return nil }
        if info == nil {
            info = PuttCapture.Audio(sampleRate: buffer.sampleRate, channels: 1,
                                     startTime: buffer.hostTime - captureStartUptime, startHostTime: buffer.hostTime,
                                     startUptime: Uptime.now)
            if let url {
                do {
                    file = try AVAudioFile(forWriting: url, settings: Self.settings(sampleRate: buffer.sampleRate),
                                           commonFormat: .pcmFormatFloat32, interleaved: false)
                } catch {
                    Log.puttLab.error("Could not create the audio file: \(String(describing: error))")
                }
            }
        }
        if let file {
            do {
                try file.write(from: Self.pcmBuffer(buffer))
            } catch {
                Log.puttLab.error("Audio write failed: \(String(describing: error))")
            }
        }
        let first = frames
        frames += buffer.samples.count
        return first
    }

    /// The buffer's samples as the mono float buffer `AVAudioFile` writes.
    private static func pcmBuffer(_ buffer: AudioSample) throws -> AVAudioPCMBuffer {
        guard !buffer.samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buffer.sampleRate, channels: 1, interleaved: false),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.samples.count)),
              let channel = pcm.floatChannelData?[0] else {
            throw CaptureAudioError.noBuffer
        }
        pcm.frameLength = AVAudioFrameCount(buffer.samples.count)
        buffer.samples.withUnsafeBufferPointer { samples in
            channel.update(from: samples.baseAddress!, count: samples.count)
        }
        return pcm
    }

    func close() {
        lock.lock()
        closed = true
        file = nil
        lock.unlock()
    }

    private static func settings(sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
}

enum CaptureAudioError: Error {
    case noBuffer
}
