import AppleArchive
import AVFAudio
import Foundation
import System

/// Packs a finished drill session's folder into one Apple Archive for the trip to the phone.
/// The audio was recorded as `audio.wav`, as in a Developer Mode round; it travels as Apple
/// Lossless only when decoding gives back exactly the same samples. Runs off the main actor,
/// after recording. See `plans/2026-10-27-putt-data-sharing.md`, section 3.2.
enum SessionPacker {
    static let losslessFile = "audio.caf"
    static let archiveExtension = "aar"
    /// Frames read and written at a time.
    private static let chunk: AVAudioFrameCount = 32_768

    enum PackError: Error {
        case archive(String)
    }

    /// Converts `audio.wav` in `folder` to `audio.caf` and checks it. Returns the audio file the
    /// archive should hold: `audio.caf` when it holds the same samples, else `audio.wav`, and
    /// then no `audio.caf` is left behind. Nil when the folder has no audio.
    static func convertAudio(in folder: URL) -> String? {
        let wav = folder.appendingPathComponent(PuttCapture.audioFile)
        let caf = folder.appendingPathComponent(losslessFile)
        guard FileManager.default.fileExists(atPath: wav.path) else { return nil }
        do {
            try toLossless(wav, caf)
            if try sameSamples(wav, caf) {
                return losslessFile
            }
            Log.puttSharing.error("Apple Lossless audio differs from the WAV; sending the WAV")
        } catch {
            Log.puttSharing.error("Could not convert the audio to Apple Lossless: \(String(describing: error)); sending the WAV")
        }
        try? FileManager.default.removeItem(at: caf)
        return PuttCapture.audioFile
    }

    /// Writes `folder`'s files into `archive`, LZFSE compressed, leaving out `audio.wav` when
    /// `audio.caf` replaces it. The WAV is deleted only once the archive is made.
    static func archive(_ folder: URL, to archive: URL, audioFile: String?) throws {
        let wav = folder.appendingPathComponent(PuttCapture.audioFile)
        let aside = folder.deletingLastPathComponent().appendingPathComponent("\(folder.lastPathComponent)-\(PuttCapture.audioFile)")
        let movesWAV = audioFile == losslessFile && FileManager.default.fileExists(atPath: wav.path)
        if movesWAV {
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.moveItem(at: wav, to: aside)
        }
        do {
            try write(folder, to: archive)
        } catch {
            if movesWAV { try? FileManager.default.moveItem(at: aside, to: wav) }
            throw error
        }
        if movesWAV { try? FileManager.default.removeItem(at: aside) }
    }

    // MARK: - Audio

    private static func toLossless(_ wav: URL, _ caf: URL) throws {
        let input = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatInt16, interleaved: true)
        let format = input.processingFormat
        try? FileManager.default.removeItem(at: caf)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitDepthHintKey: 16
        ]
        let output = try AVAudioFile(forWriting: caf, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: chunk)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
    }

    /// Whether both files decode to the same 16-bit samples.
    static func sameSamples(_ a: URL, _ b: URL) throws -> Bool {
        let first = try AVAudioFile(forReading: a, commonFormat: .pcmFormatInt16, interleaved: true)
        let second = try AVAudioFile(forReading: b, commonFormat: .pcmFormatInt16, interleaved: true)
        guard first.length == second.length, first.processingFormat == second.processingFormat,
              let x = AVAudioPCMBuffer(pcmFormat: first.processingFormat, frameCapacity: chunk),
              let y = AVAudioPCMBuffer(pcmFormat: second.processingFormat, frameCapacity: chunk) else { return false }
        let channels = Int(first.processingFormat.channelCount)
        while first.framePosition < first.length {
            try first.read(into: x, frameCount: chunk)
            try second.read(into: y, frameCount: chunk)
            guard x.frameLength == y.frameLength, let p = x.int16ChannelData?[0], let q = y.int16ChannelData?[0] else { return false }
            if memcmp(p, q, Int(x.frameLength) * channels * MemoryLayout<Int16>.size) != 0 { return false }
        }
        return true
    }

    // MARK: - Archive

    private static func write(_ folder: URL, to archive: URL) throws {
        try? FileManager.default.removeItem(at: archive)
        guard let file = ArchiveByteStream.fileStream(path: FilePath(archive.path), mode: .writeOnly,
                                                      options: [.create, .truncate],
                                                      permissions: FilePermissions(rawValue: 0o644)) else {
            throw PackError.archive("could not create \(archive.lastPathComponent)")
        }
        defer { try? file.close() }
        guard let compressed = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file) else {
            throw PackError.archive("could not start compression")
        }
        defer { try? compressed.close() }
        guard let encoder = ArchiveStream.encodeStream(writingTo: compressed) else {
            throw PackError.archive("could not start the archive")
        }
        defer { try? encoder.close() }
        guard let keys = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD,MTM") else {
            throw PackError.archive("bad field keys")
        }
        try encoder.writeDirectoryContents(archiveFrom: FilePath(folder.path), keySet: keys)
    }
}
