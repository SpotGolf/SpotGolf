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

    func testStartRoundRefusedRoundTrips() throws {
        let message = SyncMessage.startRoundRefused(StartRoundRefused(roundID: roundID, reason: .missingPermissions([.location, .health])))

        XCTAssertEqual(SyncCodec.message(in: try SyncCodec.payload(message)), message)
    }

    func testVersionRefusalRoundTrips() throws {
        let message = SyncMessage.startRoundRefused(StartRoundRefused(roundID: roundID, reason: .versionMismatch(watchVersion: "0.4.0")))

        XCTAssertEqual(SyncCodec.message(in: try SyncCodec.payload(message)), message)
    }

    func testRefusalWithOnlyMissingPermissionsIsReadAsBeforeVersionsWereChecked() throws {
        let json = #"{"roundID":"\#(roundID.uuidString)","missing":["motion"]}"#

        let refused = try JSONDecoder().decode(StartRoundRefused.self, from: Data(json.utf8))

        XCTAssertEqual(refused.reason, .missingPermissions([.motion]))
    }

    func testVersionRefusalStillWritesMissingForOlderPhones() throws {
        let data = try JSONEncoder().encode(StartRoundRefused(roundID: roundID, reason: .versionMismatch(watchVersion: "0.4.0")))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(fields["missing"] as? [String], [])
        XCTAssertEqual(fields["watchVersion"] as? String, "0.4.0")
    }

    func testPinsRoundTrip() throws {
        let pin = PinLocation(holeIndex: 3, coordinate: .init(latitude: 39.9, longitude: -105.1),
                              setAt: Date(timeIntervalSince1970: 1_700_000_000))
        let message = SyncMessage.pins(PinsMessage(roundID: roundID, pins: [pin]))

        XCTAssertEqual(SyncCodec.message(in: try SyncCodec.payload(message)), message)
    }

    func testStreamBatchWithLogLinesRoundTrips() throws {
        let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_700_000_000.25), device: .watch,
                           level: .error, category: "sensors", message: "accelerometer stalled")
        let message = SyncMessage.streamBatch(StreamBatch(roundID: roundID, from: 3, records: Data([0, 1]),
                                                          logsFrom: 7, logs: [line]))

        XCTAssertEqual(SyncCodec.message(in: try SyncCodec.payload(message)), message)
    }

    func testStreamAckWithLogsRoundTrips() throws {
        let message = SyncMessage.streamAck(StreamAck(roundID: roundID, have: 3, haveLogs: 7))

        XCTAssertEqual(SyncCodec.message(in: try SyncCodec.payload(message)), message)
    }

    func testBatchAndAckFromBeforeTheAppLogHaveNoLogFields() throws {
        let batch = #"{"streamBatch":{"_0":{"roundID":"\#(roundID.uuidString)","from":2,"records":""}}}"#
        let ack = #"{"streamAck":{"_0":{"roundID":"\#(roundID.uuidString)","have":2}}}"#

        XCTAssertEqual(try JSONDecoder().decode(SyncMessage.self, from: Data(batch.utf8)),
                       .streamBatch(StreamBatch(roundID: roundID, from: 2, records: Data())))
        XCTAssertEqual(try JSONDecoder().decode(SyncMessage.self, from: Data(ack.utf8)),
                       .streamAck(StreamAck(roundID: roundID, have: 2)))
    }

    func testStartRoundFromBeforeTheAppLogHasNoLogBaseOrDebugSetting() throws {
        let start = StartRound(roundID: roundID, date: Date(timeIntervalSince1970: 1_700_000_000), course: Data([1]),
                               holeTimeline: [], displayHole: DisplayHole(holeIndex: 0, changedAt: Date(timeIntervalSince1970: 1_700_000_000)),
                               pins: [], strokes: StrokesSnapshot(roundID: roundID, version: 0, holes: []),
                               streamBase: 4, version: "0.5.0", logBase: 9, debugLogging: true)
        var plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: try SyncCodec.encode(.startRound(start)), format: nil) as? [String: Any])
        var inner = try XCTUnwrap((plist["startRound"] as? [String: Any])?["_0"] as? [String: Any])
        inner.removeValue(forKey: "logBase")
        inner.removeValue(forKey: "debugLogging")
        plist["startRound"] = ["_0": inner]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        guard case .startRound(let decoded) = try SyncCodec.decode(data) else { return XCTFail("Not a start") }
        XCTAssertEqual(decoded.logBase, 0)
        XCTAssertFalse(decoded.debugLogging)
        XCTAssertEqual(decoded.streamBase, 4)
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
