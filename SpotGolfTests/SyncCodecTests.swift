import XCTest
@testable import SpotGolf

final class SyncCodecTests: XCTestCase {

    private let roundID = UUID()

    func testMessageRoundTrips() throws {
        let message = SyncMessage.endRound(EndRound(roundID: roundID, endedAt: Date(timeIntervalSince1970: 1_700_000_000), lastSeq: 41))

        let payload = try SyncCodec.payload(message)

        XCTAssertEqual(payload.keys.sorted(), ["m"])
        XCTAssertEqual(SyncCodec.message(in: payload), message)
    }

    func testStreamRecordsAreStoredAsRawBytes() throws {
        let records = StreamRecord.data(for: StreamFixtures.fixes(0..<1_000))
        let message = SyncMessage.streamBatch(StreamBatch(roundID: roundID, from: 0, records: records))

        let encoded = try SyncCodec.encode(message)

        // Base64 would add a third; a binary plist adds only a small header
        XCTAssertLessThan(encoded.count, records.count + 500)
    }

    func testEmptyOrUnreadablePayloadHasNoMessage() {
        XCTAssertNil(SyncCodec.message(in: [:]))
        XCTAssertNil(SyncCodec.message(in: ["m": Data([1, 2, 3])]))
        XCTAssertNil(SyncCodec.message(in: ["type": "endRound"]))
    }

    func testSmallMessageIsOnePayload() throws {
        let payloads = try SyncCodec.payloads(for: .cancelRound(CancelRound(roundID: roundID)))

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(SyncCodec.message(in: payloads[0]), .cancelRound(CancelRound(roundID: roundID)))
    }

    func testLargeMessageIsSplitIntoChunksUnderTheLimit() throws {
        let message = largeMessage()

        let payloads = try SyncCodec.payloads(for: message)

        XCTAssertGreaterThan(payloads.count, 1)
        for payload in payloads {
            let data = try XCTUnwrap(payload["m"] as? Data)
            XCTAssertLessThanOrEqual(data.count, SyncCodec.maxMessageBytes)
            guard case .chunk = SyncCodec.message(in: payload) else {
                return XCTFail("Every payload should be a chunk")
            }
        }
    }

    func testChunksJoinInAnyOrder() throws {
        let message = largeMessage()
        let chunks = try SyncCodec.payloads(for: message).compactMap { payload -> SyncChunk? in
            guard case .chunk(let chunk) = SyncCodec.message(in: payload) else { return nil }
            return chunk
        }
        var assembler = ChunkAssembler()

        var results: [SyncMessage] = []
        for chunk in chunks.reversed() {
            if let whole = assembler.add(chunk) {
                results.append(whole)
            }
        }

        XCTAssertEqual(results, [message])
        XCTAssertFalse(assembler.hasTransfers)
    }

    func testRepeatedChunkDoesNotCompleteEarly() throws {
        let chunks = SyncCodec.chunks(of: try SyncCodec.encode(largeMessage()))
        var assembler = ChunkAssembler()

        XCTAssertNil(assembler.add(chunks[0]))
        XCTAssertNil(assembler.add(chunks[0]))
        XCTAssertTrue(assembler.hasTransfers)
    }

    func testUnfinishedTransferIsDroppedAfterMaxAge() throws {
        let chunks = SyncCodec.chunks(of: try SyncCodec.encode(largeMessage()))
        let start = Date()
        var assembler = ChunkAssembler()
        XCTAssertNil(assembler.add(chunks[0], now: start))

        // The rest arrive too late: the first chunk is gone, so the message never completes
        for chunk in chunks.dropFirst() {
            XCTAssertNil(assembler.add(chunk, now: start.addingTimeInterval(ChunkAssembler.maxAge + 1)))
        }
    }

    /// A stream batch too large for one message.
    private func largeMessage() -> SyncMessage {
        var random = SystemRandomNumberGenerator()
        let bytes = (0..<150_000).map { _ in UInt8.random(in: 0...255, using: &random) }
        return .streamBatch(StreamBatch(roundID: roundID, from: 0, records: Data(bytes)))
    }
}
