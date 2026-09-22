import Foundation
import WatchConnectivity
import CourseDataSwift

private let syncDateFormatter = ISO8601DateFormatter()

@MainActor
class SyncService: NSObject, ObservableObject {

    var roundStore: RoundStore? {
        didSet { bindSyncHandler() }
    }
    var guessStore: GuessStore?
    var settingsStore: SettingsStore?
    var trackStore: TrackStore?

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

    private var trackSyncTimer: Timer?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        #if os(watchOS)
        // GPS fixes drive sends during play; this covers the tail once fixes stop
        trackSyncTimer = Timer.scheduledTimer(withTimeInterval: Self.trackSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPendingTracks()
            }
        }
        #endif
    }

    private func bindSyncHandler() {
        roundStore?.onSyncEvent = { [weak self] message in
            self?.send(message)
        }
    }

    nonisolated func send(_ message: SyncMessage) {
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

        case .setHole(let holeIndex, let roundID, let changedAt):
            sendPayload([
                "type": "setHole",
                "roundId": roundID.uuidString,
                "holeIndex": holeIndex,
                "changedAt": changedAt.timeIntervalSince1970
            ], via: session)

        case .setMarkType(let markID, let markType, let roundID):
            sendPayload([
                "type": "setMarkType",
                "markId": markID.uuidString,
                "markType": markType.rawValue,
                "roundId": roundID.uuidString
            ], via: session)

        case .addGuess(let guess, let roundID):
            guard let data = try? JSONEncoder().encode(guess) else { return }
            sendPayload([
                "type": "addGuess",
                "roundId": roundID.uuidString,
                "guess": data
            ], via: session)

        case .removeGuess(let guessID, let roundID):
            sendPayload([
                "type": "removeGuess",
                "guessId": guessID.uuidString,
                "roundId": roundID.uuidString
            ], via: session)

        case .updateSettings(let settings):
            guard let data = try? JSONEncoder().encode(settings) else { return }
            sendPayload([
                "type": "updateSettings",
                "settings": data
            ], via: session)
        }
    }

    // MARK: - Send Helpers

    private func sendPayload(_ payload: [String: Any], via session: WCSession) {
        // Always queue via transferUserInfo for guaranteed delivery
        session.transferUserInfo(payload)

        // Also try sendMessage for instant delivery when reachable
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[Sync] sendMessage failed (transferUserInfo will deliver): \(error)")
            }
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

    // MARK: - Tracks

    /// How often the watch ships track segments during a round.
    static let trackSyncInterval: TimeInterval = 15

    private var lastTrackSync = Date.distantPast

    /// Rate-limited `sendPendingTracks()` — call on every GPS fix so the phone's
    /// view of the path stays fresh without a transfer per fix.
    func sendPendingTracksIfDue() {
        guard Date().timeIntervalSince(lastTrackSync) >= Self.trackSyncInterval else { return }
        lastTrackSync = Date()
        sendPendingTracks()
    }

    // Outbox files currently being sent as messages, awaiting the phone's reply
    private var trackMessagesInFlight: Set<String> = []

    /// Sends the watch's GPS track segments to the phone. A reachable phone gets
    /// them as messages for immediate delivery (file transfers do not arrive
    /// between simulators and can lag on hardware). While unreachable, an active
    /// round's segments wait in the outbox for the next timer tick or reachability
    /// change; only finished rounds use background file transfers.
    func sendPendingTracks() {
        #if os(watchOS)
        guard let session, session.activationState == .activated,
              let trackStore else { return }

        trackStore.moveTracksToOutbox()

        let activeRoundID = roundStore?.activeRound?.id
        let inFlight = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for url in trackStore.outboxFiles()
        where !inFlight.contains(url.lastPathComponent) && !trackMessagesInFlight.contains(url.lastPathComponent) {
            guard let info = TrackStore.parseFileName(url) else { continue }
            if session.isReachable,
               let data = try? Data(contentsOf: url),
               data.count <= Self.chunkSize {
                sendTrackSegment(data, roundID: info.roundID, source: info.source, url: url, via: session)
            } else if info.roundID != activeRoundID {
                session.transferFile(url, metadata: [
                    "type": "track",
                    "roundId": info.roundID.uuidString,
                    "source": info.source.rawValue
                ])
            }
        }
        #endif
    }

    /// The outbox file is only removed once the phone replies, so a failed send
    /// is retried by the next `sendPendingTracks()`.
    private func sendTrackSegment(_ data: Data, roundID: UUID, source: TrackSource, url: URL, via session: WCSession) {
        trackMessagesInFlight.insert(url.lastPathComponent)
        session.sendMessage([
            "type": "trackSegment",
            "roundId": roundID.uuidString,
            "source": source.rawValue,
            "data": data
        ], replyHandler: { [weak self] _ in
            Task { @MainActor in
                self?.trackMessagesInFlight.remove(url.lastPathComponent)
                self?.trackStore?.removeOutboxFile(url)
            }
        }, errorHandler: { [weak self] error in
            print("[Sync] Track segment message failed: \(error)")
            Task { @MainActor in
                self?.trackMessagesInFlight.remove(url.lastPathComponent)
            }
        })
    }

    func handleReceivedTrack(at url: URL, roundID: UUID, source: TrackSource) {
        // A file can arrive before the app has wired its stores; the files on disk are the truth
        (trackStore ?? TrackStore()).importSegment(from: url, roundID: roundID, source: source)
        try? FileManager.default.removeItem(at: url)
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

        case "setHole":
            guard let idString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: idString),
                  let holeIndex = message["holeIndex"] as? Int,
                  let changedAt = message["changedAt"] as? Double else { return }
            roundStore?.setHoleIndex(holeIndex, roundID: roundID,
                                     changedAt: Date(timeIntervalSince1970: changedAt), fromSync: true)

        case "setMarkType":
            guard let markIdString = message["markId"] as? String,
                  let markID = UUID(uuidString: markIdString),
                  let typeString = message["markType"] as? String,
                  let markType = BallMarkType(rawValue: typeString),
                  let roundIdString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: roundIdString) else { return }
            roundStore?.setMarkType(markID: markID, type: markType, in: roundID, fromSync: true)

        case "addGuess":
            guard let data = message["guess"] as? Data,
                  let guess = try? JSONDecoder().decode(MissedMarkGuess.self, from: data) else { return }
            guessStore?.add(guess)

        case "removeGuess":
            guard let guessIdString = message["guessId"] as? String,
                  let guessID = UUID(uuidString: guessIdString),
                  let roundIdString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: roundIdString) else { return }
            guessStore?.remove(guessID: guessID, roundID: roundID)

        case "trackSegment":
            guard let idString = message["roundId"] as? String,
                  let roundID = UUID(uuidString: idString),
                  let sourceString = message["source"] as? String,
                  let source = TrackSource(rawValue: sourceString),
                  let data = message["data"] as? Data else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(TrackStore.fileExtension)")
            do {
                try data.write(to: url)
            } catch {
                print("[Sync] Failed to store received track segment: \(error)")
                return
            }
            handleReceivedTrack(at: url, roundID: roundID, source: source)

        case "updateSettings":
            guard let data = message["settings"] as? Data,
                  let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
            settingsStore?.apply(settings)

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
        Task { @MainActor in
            self.updateConnectionStatus()
            self.sendPendingTracks()
        }
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

    /// Senders that need delivery confirmation (track segments) use the reply variant.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handleMessage(message)
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handleMessage(userInfo) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["type"] as? String == "track",
              let idString = file.metadata?["roundId"] as? String,
              let roundID = UUID(uuidString: idString),
              let sourceString = file.metadata?["source"] as? String,
              let source = TrackSource(rawValue: sourceString) else { return }

        // The system deletes the file when this method returns, so copy it first
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(TrackStore.fileExtension)")
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: copy)
        } catch {
            print("[Sync] Failed to copy received track: \(error)")
            return
        }
        Task { @MainActor in
            self.handleReceivedTrack(at: copy, roundID: roundID, source: source)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        Task { @MainActor in
            if let error {
                // The file stays in the outbox and is sent again by the next sendPendingTracks()
                print("[Sync] Track transfer failed: \(error)")
                return
            }
            self.trackStore?.removeOutboxFile(url)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        print("[Sync] Reachability changed: \(session.isReachable)")
        Task { @MainActor in
            self.updateConnectionStatus()
            if session.isReachable, let pending = self.pendingChunkedSend {
                print("[Sync] Watch reachable – sending queued chunked transfer")
                self.sendChunked(data: pending.data, metadata: pending.metadata, via: session)
            }
            if session.isReachable {
                self.sendPendingTracks()
            }
        }
    }
}
