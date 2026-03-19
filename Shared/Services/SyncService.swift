import Foundation
import WatchConnectivity
import CourseData

private let syncDateFormatter = ISO8601DateFormatter()

@MainActor
class SyncService: NSObject, ObservableObject {

    var roundStore: RoundStore? {
        didSet { bindSyncHandler() }
    }

    @Published var isConnected = false
    @Published var isReceivingCourse = false
    @Published var syncError: String?

    private var session: WCSession?

    // Chunked transfer reassembly
    private var pendingChunks: [String: ChunkedTransfer] = [:]

    private struct ChunkedTransfer {
        let totalChunks: Int
        let totalBytes: Int
        let metadata: [String: Any]
        var receivedChunks: [Int: Data]

        var isComplete: Bool { receivedChunks.count == totalChunks }

        var assembledData: Data? {
            guard isComplete else { return nil }
            var result = Data(capacity: totalBytes)
            for i in 0..<totalChunks {
                guard let chunk = receivedChunks[i] else { return nil }
                result.append(chunk)
            }
            return result
        }
    }

    private static let chunkSize = 40_000 // ~40KB per chunk, well under 64KB sendMessage limit

    // Queued chunked transfer for when watch is unreachable
    private var pendingChunkedSend: (data: Data, metadata: [String: Any])?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    private func bindSyncHandler() {
        roundStore?.onSyncEvent = { [weak self] message in
            self?.send(message)
        }
    }

    private nonisolated func send(_ message: SyncMessage) {
        Task { @MainActor in
            self.sendOnMain(message)
        }
    }

    private func sendOnMain(_ message: SyncMessage) {
        guard let session, session.activationState == .activated else {
            print("[Sync] Cannot send – session not activated")
            return
        }

        switch message {
        case .startRound(let id, let date):
            sendPayload([
                "type": "startRound",
                "id": id.uuidString,
                "date": syncDateFormatter.string(from: date)
            ], via: session)

        case .endRound(let id):
            sendPayload([
                "type": "endRound",
                "id": id.uuidString
            ], via: session)

        case .addMark(let mark, let holeIndex, let roundID):
            guard let data = try? JSONEncoder().encode(mark) else { return }
            sendPayload([
                "type": "addMark",
                "roundId": roundID.uuidString,
                "holeIndex": holeIndex,
                "mark": data
            ], via: session)

        case .setCourse(let selection, let roundID):
            do {
                let data = try JSONEncoder().encode(selection.trimmed)
                let compressed = try data.gzipCompressed()
                sendChunked(
                    data: compressed,
                    metadata: ["type": "setCourse", "roundId": roundID.uuidString],
                    via: session
                )
            } catch {
                print("[Sync] Failed to encode/compress course: \(error)")
                syncError = "Could not sync course data to the watch."
            }

        case .setMarkType(let markID, let markType, let roundID):
            sendPayload([
                "type": "setMarkType",
                "markId": markID.uuidString,
                "markType": markType.rawValue,
                "roundId": roundID.uuidString
            ], via: session)
        }
    }

    // MARK: - Send Helpers

    private func sendPayload(_ payload: [String: Any], via session: WCSession) {
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[Sync] sendMessage failed: \(error)")
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func sendChunked(data: Data, metadata: [String: Any], via session: WCSession) {
        guard session.isReachable else {
            print("[Sync] Watch unreachable – queuing chunked transfer")
            pendingChunkedSend = (data, metadata)
            return
        }
        pendingChunkedSend = nil

        let transferID = UUID().uuidString
        let totalChunks = (data.count + Self.chunkSize - 1) / Self.chunkSize

        // Send header
        var header = metadata
        header["_chunked"] = true
        header["_transferId"] = transferID
        header["_totalChunks"] = totalChunks
        header["_totalBytes"] = data.count
        print("[Sync] Sending chunked: \(totalChunks) chunks, \(data.count) bytes")

        session.sendMessage(header, replyHandler: nil) { error in
            print("[Sync] Chunk header failed: \(error)")
        }

        // Send chunks
        for i in 0..<totalChunks {
            let start = i * Self.chunkSize
            let end = min(start + Self.chunkSize, data.count)
            let chunkData = data[start..<end]

            let chunkPayload: [String: Any] = [
                "_chunk": true,
                "_transferId": transferID,
                "_chunkIndex": i,
                "_data": Data(chunkData)
            ]
            session.sendMessage(chunkPayload, replyHandler: nil) { error in
                print("[Sync] Chunk \(i) failed: \(error)")
            }
        }
    }

    // MARK: - Receive

    func handleMessage(_ message: [String: Any]) {
        // Chunked transfer: header
        if message["_chunked"] as? Bool == true {
            guard let transferID = message["_transferId"] as? String,
                  let totalChunks = message["_totalChunks"] as? Int,
                  let totalBytes = message["_totalBytes"] as? Int else { return }
            pendingChunks[transferID] = ChunkedTransfer(
                totalChunks: totalChunks,
                totalBytes: totalBytes,
                metadata: message,
                receivedChunks: [:]
            )
            isReceivingCourse = true
            print("[Sync] Receiving chunked: \(totalChunks) chunks, \(totalBytes) bytes")
            return
        }

        // Chunked transfer: chunk
        if message["_chunk"] as? Bool == true {
            guard let transferID = message["_transferId"] as? String,
                  let chunkIndex = message["_chunkIndex"] as? Int,
                  let data = message["_data"] as? Data else { return }
            pendingChunks[transferID]?.receivedChunks[chunkIndex] = data

            if let transfer = pendingChunks[transferID], transfer.isComplete {
                pendingChunks.removeValue(forKey: transferID)
                isReceivingCourse = false
                print("[Sync] Chunked transfer complete")
                if let assembled = transfer.assembledData {
                    handleChunkedPayload(metadata: transfer.metadata, data: assembled)
                }
            }
            return
        }

        // Regular messages
        guard let type = message["type"] as? String else { return }

        switch type {
        case "startRound":
            guard let idString = message["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let dateString = message["date"] as? String,
                  let date = syncDateFormatter.date(from: dateString) else { return }
            roundStore?.startRound(id: id, date: date, fromSync: true)

        case "endRound":
            guard let idString = message["id"] as? String,
                  let id = UUID(uuidString: idString) else { return }
            roundStore?.endRound(roundID: id, fromSync: true)

        case "addMark":
            guard let data = message["mark"] as? Data,
                  let idString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: idString),
                  let holeIndex = message["holeIndex"] as? Int,
                  let mark = try? JSONDecoder().decode(BallMark.self, from: data) else { return }
            roundStore?.addMark(to: roundID, holeIndex: holeIndex, mark: mark, fromSync: true)

        case "setMarkType":
            guard let markIdString = message["markId"] as? String,
                  let markID = UUID(uuidString: markIdString),
                  let typeString = message["markType"] as? String,
                  let markType = BallMarkType(rawValue: typeString),
                  let roundIdString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: roundIdString) else { return }
            roundStore?.setMarkType(markID: markID, type: markType, in: roundID, fromSync: true)

        default:
            break
        }
    }

    private func handleChunkedPayload(metadata: [String: Any], data: Data) {
        guard let type = metadata["type"] as? String else { return }

        switch type {
        case "setCourse":
            guard let idString = metadata["roundId"] as? String,
                  let roundID = UUID(uuidString: idString) else { return }
            do {
                let decompressed = try data.gzipDecompressed()
                let selection = try JSONDecoder().decode(CourseSelection.self, from: decompressed)
                roundStore?.setCourse(selection, for: roundID, fromSync: true)
            } catch {
                print("[Sync] Failed to decode chunked course data: \(error)")
            }

        default:
            break
        }
    }

    private func updateConnectionStatus() {
        guard let session else {
            isConnected = false
            return
        }
        isConnected = session.activationState == .activated && session.isReachable
    }
}

extension SyncService: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[Sync] WCSession activation failed: \(error)")
        } else {
            print("[Sync] WCSession activated – state: \(activationState.rawValue), reachable: \(session.isReachable)")
        }
        Task { @MainActor in self.updateConnectionStatus() }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handleMessage(message) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handleMessage(userInfo) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        print("[Sync] Reachability changed: \(session.isReachable)")
        Task { @MainActor in
            self.updateConnectionStatus()
            if session.isReachable, let pending = self.pendingChunkedSend {
                print("[Sync] Watch reachable – sending queued chunked transfer")
                self.sendChunked(data: pending.data, metadata: pending.metadata, via: session)
            }
        }
    }
}
