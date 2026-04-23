import Foundation

enum OpenAITTSVoice: String, CaseIterable, Identifiable {
    case alloy, echo, fable, onyx, nova, shimmer
    var id: String { rawValue }
    var displayName: String { "\(rawValue.capitalized) (\(descriptor))" }

    /// One-word character descriptors drawn from OpenAI's TTS voice guide.
    private var descriptor: String {
        switch self {
        case .alloy:   "Neutral"
        case .echo:    "Resonant"
        case .fable:   "Expressive"
        case .onyx:    "Deep"
        case .nova:    "Bright"
        case .shimmer: "Soft"
        }
    }
}

enum OpenAITTSModel: String, CaseIterable, Identifiable {
    case tts_1 = "tts-1"
    case tts_1_hd = "tts-1-hd"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .tts_1:    "Standard"
        case .tts_1_hd: "HD"
        }
    }
}

enum OpenAIDJVoiceError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse(status: Int, body: String)
    case serverError(underlying: Error)
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "OpenAI API key not set. Add it in Settings."
        case .invalidResponse(let status, let body):
            "OpenAI TTS returned HTTP \(status). \(body)"
        case .serverError(let e):
            "OpenAI TTS failed: \(e.localizedDescription)"
        }
    }
}

/// Renders DJ scripts via OpenAI's /v1/audio/speech endpoint and writes the
/// returned MP3 bytes to a temp file.
final class OpenAIDJVoice: DJVoiceProtocol, @unchecked Sendable {

    private let session: URLSession
    private let lock = NSLock()
    private var _model: OpenAITTSModel = .tts_1

    private var model: OpenAITTSModel {
        get { lock.lock(); defer { lock.unlock() }; return _model }
        set { lock.lock(); _model = newValue; lock.unlock() }
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func updateModel(_ model: OpenAITTSModel) {
        self.model = model
    }

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        guard let apiKey = Keychain.get(KeychainKey.openAIAPIKey), !apiKey.isEmpty else {
            throw OpenAIDJVoiceError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let activeModel = model
        let voice = OpenAITTSVoice(rawValue: voiceIdentifier) ?? .alloy
        let body: [String: Any] = [
            "model": activeModel.rawValue,
            "voice": voice.rawValue,
            "input": script,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Log.voice.info("OpenAI TTS request (model=\(activeModel.rawValue, privacy: .public), voice=\(voice.rawValue, privacy: .public), chars=\(script.count))")

        let started = ContinuousClock.now
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIDJVoiceError.serverError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenAIDJVoiceError.invalidResponse(status: status, body: body)
        }

        let elapsed = ContinuousClock.now - started
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try data.write(to: outputURL)
        Log.voice.info("OpenAI TTS rendered in \(String(describing: elapsed), privacy: .public) → \(outputURL.lastPathComponent, privacy: .public) (\(data.count) bytes)")
        return outputURL
    }
}
