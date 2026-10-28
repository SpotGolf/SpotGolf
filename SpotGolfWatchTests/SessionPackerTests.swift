import AppleArchive
import AVFAudio
import System
import XCTest
@testable import SpotGolfWatch

/// Packing a finished session: the audio as Apple Lossless only when it decodes to the same
/// samples, and the folder as one Apple Archive.
final class SessionPackerTests: XCTestCase {
    private var folder: URL!
    private var work: URL!

    override func setUp() {
        super.setUp()
        work = FileManager.default.temporaryDirectory.appendingPathComponent("packer-\(UUID().uuidString)", isDirectory: true)
        folder = work.appendingPathComponent("session", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: work)
        super.tearDown()
    }

    /// A 16-bit WAV written the way `CaptureAudioWriter` writes one: noise with a click.
    private func makeWAV(_ url: URL, seconds: Double = 2, seed: UInt64 = 1) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000.0,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(48_000 * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        var random = SplitMix(seed: seed)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) {
            samples[index] = Float(random.next() % 2_000) / 100_000 - 0.01
        }
        let click = Int(frames) / 2
        for index in click..<(click + 48) {
            samples[index] = index % 2 == 0 ? 0.8 : -0.8
        }
        try file.write(from: buffer)
    }

    private func write(_ text: String, _ name: String) throws {
        try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }

    private func extract(_ archive: URL) throws -> URL {
        let destination = work.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = try XCTUnwrap(ArchiveByteStream.fileStream(path: FilePath(archive.path), mode: .readOnly, options: [],
                                                              permissions: FilePermissions(rawValue: 0o644)))
        defer { try? file.close() }
        let decompressed = try XCTUnwrap(ArchiveByteStream.decompressionStream(readingFrom: file))
        defer { try? decompressed.close() }
        let decoder = try XCTUnwrap(ArchiveStream.decodeStream(readingFrom: decompressed))
        defer { try? decoder.close() }
        let extractor = try XCTUnwrap(ArchiveStream.extractStream(extractingTo: FilePath(destination.path)))
        defer { try? extractor.close() }
        _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
        return destination
    }

    func testAudioTravelsAsAppleLosslessWithTheSameSamples() throws {
        let wav = folder.appendingPathComponent(PuttCapture.audioFile)
        try makeWAV(wav)

        let audio = SessionPacker.convertAudio(in: folder)

        XCTAssertEqual(audio, SessionPacker.losslessFile)
        let caf = folder.appendingPathComponent(SessionPacker.losslessFile)
        XCTAssertTrue(try SessionPacker.sameSamples(wav, caf))
        let wavSize = try XCTUnwrap(try wav.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let cafSize = try XCTUnwrap(try caf.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThan(cafSize, wavSize, "Lossless is smaller")
        print("Apple Lossless: \(cafSize) of \(wavSize) bytes")
    }

    func testDifferentAudioIsNotTheSame() throws {
        let a = work.appendingPathComponent("a.wav"), b = work.appendingPathComponent("b.wav")
        try makeWAV(a, seed: 1)
        try makeWAV(b, seed: 2)

        XCTAssertFalse(try SessionPacker.sameSamples(a, b))
    }

    func testAudioThatCannotBeConvertedTravelsAsTheWAV() throws {
        // Not audio at all, so the conversion fails
        try write("not audio", PuttCapture.audioFile)

        XCTAssertEqual(SessionPacker.convertAudio(in: folder), PuttCapture.audioFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(SessionPacker.losslessFile).path))
    }

    func testNoAudioIsNoAudioFile() {
        XCTAssertNil(SessionPacker.convertAudio(in: folder))
    }

    func testArchiveHoldsTheFilesWithTheLosslessAudioInsteadOfTheWAV() throws {
        try makeWAV(folder.appendingPathComponent(PuttCapture.audioFile))
        try write("{\"version\":1}", DrillSession.Record.file)
        try write("t,event,value\n1,ready,1\n", PuttCapture.eventsFile)
        let audio = SessionPacker.convertAudio(in: folder)
        let caf = try Data(contentsOf: folder.appendingPathComponent(SessionPacker.losslessFile))
        let archive = work.appendingPathComponent("session.aar")

        try SessionPacker.archive(folder, to: archive, audioFile: audio)

        let extracted = try extract(archive)
        let names = try FileManager.default.contentsOfDirectory(atPath: extracted.path).sorted()
        XCTAssertEqual(names, [PuttCapture.eventsFile, SessionPacker.losslessFile, DrillSession.Record.file].sorted())
        XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent(SessionPacker.losslessFile)), caf)
        XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent(PuttCapture.eventsFile), encoding: .utf8),
                       "t,event,value\n1,ready,1\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(PuttCapture.audioFile).path),
                       "The WAV is deleted once the archive is made")
    }

    func testArchiveKeepsTheWAVWhenItIsTheAudio() throws {
        try write("not audio", PuttCapture.audioFile)
        let archive = work.appendingPathComponent("session.aar")

        try SessionPacker.archive(folder, to: archive, audioFile: PuttCapture.audioFile)

        let extracted = try extract(archive)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: extracted.path), [PuttCapture.audioFile])
    }

    func testPackingASessionWritesItsInfoAndRemovesTheFolder() throws {
        try makeWAV(folder.appendingPathComponent(PuttCapture.audioFile), seconds: 0.5)
        let id = UUID()
        let info = PuttSharing.Info(sessionID: id, appVersion: "1.0.0", watchModel: "Watch7,1", watchOSVersion: "26.0",
                                    consentVersion: 1, sharerID: UUID(), equipment: PuttSharing.Equipment(),
                                    location: nil, locationStatus: .noFix, audioFile: nil)
        let outbox = work.appendingPathComponent("outbox", isDirectory: true)

        let archive = try XCTUnwrap(DrillRecorder.packSession(folder, info: info, outbox: outbox))

        XCTAssertEqual(archive.lastPathComponent, "\(id.uuidString).aar")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        let extracted = try extract(archive)
        let written = try JSONDecoder().decode(PuttSharing.Info.self,
                                               from: Data(contentsOf: extracted.appendingPathComponent(PuttSharing.Info.file)))
        XCTAssertEqual(written.audioFile, SessionPacker.losslessFile)
        XCTAssertEqual(written.locationStatus, .noFix)
    }
}

/// Repeatable noise for test audio.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
