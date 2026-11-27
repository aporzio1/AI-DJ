import Foundation
import AVFAudio

/// Microsoft Edge readaloud TTS — free neural voices over the consumer
/// endpoint the `edge-tts` tooling uses (no key, no quota). WebSocket in,
/// 24 kHz mono MP3 out, transcoded to the .caf contract the player expects.
///
/// Wire protocol mirrors edge-tts exactly: Sec-MS-GEC signed handshake
/// (EdgeDRM), browser headers + muid cookie, speech.config preamble, then a
/// Path:ssml frame. The DJ must never wait on the network: a hard deadline
/// bounds every render and misses fall through to the offline Sherpa tier.
final class EdgeTTSDJVoice: DJVoiceProtocol, @unchecked Sendable {
    private var defaultVoice: String {
        UserDefaults.standard.string(forKey: "edgeVoice") ?? "en-US-AriaNeural"
    }
    private let renderDeadline: TimeInterval = 6.0

    private static let origin = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"
    private static let browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"

    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = renderDeadline + 0.5
        session = URLSession(configuration: config)
    }

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        // "Connection reset by peer" is a transient socket hiccup, not a
        // protocol rejection — one retry keeps Aria on the mic instead of
        // handing the night to the 17 s CPU fallback.
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await renderOnce(script: script)
            } catch {
                if attempt >= 2 || error is DJVoiceError { throw error }
            }
        }
    }

    private func renderOnce(script: String) async throws -> URL {
        let text = SherpaKokoroDJVoice.normalize(script)
        guard !text.isEmpty else { throw DJVoiceError.noAudioRendered }
        let t0 = Date()

        let audio = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let connectID = UUID().uuidString
            let gec = EdgeDRM.secMsGEC(unixTimestamp: Date().timeIntervalSince1970)
            guard let url = URL(string:
                "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
                + "?TrustedClientToken=\(EdgeDRM.trustedClientToken)"
                + "&ConnectionId=\(connectID)"
                + "&Sec-MS-GEC=\(gec)"
                + "&Sec-MS-GEC-Version=\(EdgeDRM.gecVersion)") else {
                cont.resume(throwing: DJVoiceError.noAudioRendered); return
            }
            var request = URLRequest(url: url)
            request.setValue(Self.browserUA, forHTTPHeaderField: "User-Agent")
            request.setValue(Self.origin, forHTTPHeaderField: "Origin")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("muid=\(UUID().uuidString.uppercased());", forHTTPHeaderField: "Cookie")

            let task = session.webSocketTask(with: request)
            let box = EdgeReceiveBox(cont: cont)

            // speech.config preamble, then the SSML turn — edge-tts sends both
            // before reading a single byte back.
            let configFrame = "X-Timestamp:\(Self.edgeTimestamp())\r\n"
                + "Content-Type:application/json; charset=utf-8\r\n"
                + "Path:speech.config\r\n\r\n"
                + "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{"
                + "\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\""
                + "},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"
            let ssmlFrame = "X-RequestId:\(connectID)\r\n"
                + "Content-Type:application/ssml+xml\r\n"
                + "X-Timestamp:\(Self.edgeTimestamp())Z\r\n"  // trailing Z is intentional (edge parity)
                + "Path:ssml\r\n\r\n"
                + "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
                + "<voice name='\(self.defaultVoice)'>\(Self.escape(text))</voice></speak>"

            task.resume()
            task.send(.string(configFrame)) { error in
                if let error { task.cancel(); box.fail(error) }
                task.send(.string(ssmlFrame)) { error2 in
                    if let error2 { task.cancel(); box.fail(error2) }
                }
            }
            box.pump(task)

            Task {
                try? await Task.sleep(for: .seconds(self.renderDeadline))
                if !Task.isCancelled {
                    box.fail(DJVoiceError.renderTimeout)
                    task.cancel(with: .goingAway, reason: nil)
                }
            }
        }

        guard !audio.isEmpty else { throw DJVoiceError.noAudioRendered }
        logEngine("EDGE-OK \(audio.count)B in \(Int(Date().timeIntervalSince(t0) * 1000))ms")
        return try Self.transcodeToCAF(mp3: audio)
    }

    /// edge-tts' `date_to_string()`: literal "GMT+0000 (Coordinated Universal Time)"
    /// suffix whatever the local zone — the service only echoes it back.
    private static func edgeTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: Date())
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 24 kHz MP3 → int16 CAF so the player sees one format from every tier.
    private static func transcodeToCAF(mp3: Data) throws -> URL {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp3")
        try mp3.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let reader = try AVAudioFile(forReading: source)
        let format = reader.processingFormat
        let total = AVAudioFrameCount(reader.length)
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: total) else { throw DJVoiceError.noAudioRendered }
        try reader.read(into: buffer)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        let writer = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        try writer.write(from: buffer)
        return outputURL
    }
}

/// Accumulates binary frames (2-byte header length, then MP3 bytes) and
/// resolves once the service reports turn.end — or the deadline fires.
private final class EdgeReceiveBox: @unchecked Sendable {
    private let cont: CheckedContinuation<Data, Error>
    private var audio = Data()
    private var texts: [String] = []
    private var bins = 0
    private var done = false
    private let lock = NSLock()

    init(cont: CheckedContinuation<Data, Error>) { self.cont = cont }

    func pump(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                if self.audio.isEmpty { self.fail(error) } else { self.finish() }
            case .success(.data(let chunk)):
                self.lock.lock()
                self.bins += 1
                if chunk.count > 2 {
                    // Wire format: 2-byte BIG-endian header length. Load raw
                    // bytes — the old load(as: UInt16.self) + .bigEndian combo
                    // byte-swapped on arm64 and shredded the MP3 stream.
                    let headerLen = Int(chunk[0]) << 8 | Int(chunk[1])
                    if headerLen > 0, chunk.count > 2 + headerLen {
                        self.audio.append(chunk.dropFirst(2 + headerLen))
                    }
                }
                self.lock.unlock()
                self.pump(task)
            case .success(.string(let text)):
                if texts.count < 4 { texts.append(String(text.prefix(200))) }
                if text.contains("turn.end") { self.finish() } else { self.pump(task) }
            @unknown default:
                self.pump(task)
            }
        }
    }

    func fail(_ error: Error) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        lock.unlock()
        cont.resume(throwing: error)
    }

    private func finish() {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let empty = audio.isEmpty
        let snapshot = (bins, texts.prefix(3).joined(separator: " || "))
        lock.unlock()
        if empty { logEngine("EDGE-EMPTY bins=\(snapshot.0) srv=[\(snapshot.1)]") }
        cont.resume(returning: audio)
    }
}
