import Foundation

@Observable
@MainActor
final class SettingsViewModel {

    var persona: DJPersona = .default
    var djEnabled: Bool = true
    var newsEnabled: Bool = true
    var feedURLStrings: [String] = []
    var listenerName: String = ""
    var voiceIdentifier: String = ""
    var ttsProvider: TTSProvider = .system
    var openAIVoice: String = OpenAITTSVoice.alloy.rawValue
    var openAIModel: String = OpenAITTSModel.tts_1.rawValue
    var openAIAPIKey: String = ""   // mirrored in Keychain; this is the in-memory copy for the SecureField
    var kokoroVoice: String = KokoroVoice.defaultVoice.rawValue

    private static let feedsKey = "rssFeedURLs"
    private static let djEnabledKey = "djEnabled"
    private static let newsEnabledKey = "newsEnabled"
    private static let listenerNameKey = "listenerName"
    private static let voiceIdentifierKey = "voiceIdentifier"
    private static let ttsProviderKey = "ttsProvider"
    private static let openAIVoiceKey = "openAIVoice"
    private static let openAIModelKey = "openAIModel"
    private static let kokoroVoiceKey = "kokoroVoice"

    init() {
        loadFromUserDefaults()
    }

    // MARK: RSS Feed management

    func addFeed(urlString: String) {
        guard !urlString.isEmpty, URL(string: urlString) != nil else { return }
        guard !feedURLStrings.contains(urlString) else { return }
        feedURLStrings.append(urlString)
        saveToUserDefaults()
    }

    func removeFeed(at offsets: IndexSet) {
        feedURLStrings.remove(atOffsets: offsets)
        saveToUserDefaults()
    }

    func importOPML(data: Data) {
        let urls = OPMLParser.parse(data: data)
        for url in urls where !feedURLStrings.contains(url) {
            feedURLStrings.append(url)
        }
        saveToUserDefaults()
    }

    var feedURLs: [URL] {
        feedURLStrings.compactMap { URL(string: $0) }
    }

    // MARK: Persistence

    func save() {
        saveToUserDefaults()
    }

    private func saveToUserDefaults() {
        UserDefaults.standard.set(feedURLStrings, forKey: Self.feedsKey)
        UserDefaults.standard.set(djEnabled, forKey: Self.djEnabledKey)
        UserDefaults.standard.set(newsEnabled, forKey: Self.newsEnabledKey)
        UserDefaults.standard.set(listenerName, forKey: Self.listenerNameKey)
        UserDefaults.standard.set(voiceIdentifier, forKey: Self.voiceIdentifierKey)
        UserDefaults.standard.set(ttsProvider.rawValue, forKey: Self.ttsProviderKey)
        UserDefaults.standard.set(openAIVoice, forKey: Self.openAIVoiceKey)
        UserDefaults.standard.set(openAIModel, forKey: Self.openAIModelKey)
        UserDefaults.standard.set(kokoroVoice, forKey: Self.kokoroVoiceKey)
        // API key is persisted to Keychain via saveAPIKey(); not echoed to UserDefaults.
    }

    private func loadFromUserDefaults() {
        feedURLStrings = UserDefaults.standard.stringArray(forKey: Self.feedsKey) ?? []
        djEnabled = UserDefaults.standard.object(forKey: Self.djEnabledKey) as? Bool ?? true
        newsEnabled = UserDefaults.standard.object(forKey: Self.newsEnabledKey) as? Bool ?? true
        if let stored = UserDefaults.standard.string(forKey: Self.listenerNameKey), !stored.isEmpty {
            listenerName = stored
        } else {
            listenerName = defaultSystemName()
        }
        voiceIdentifier = UserDefaults.standard.string(forKey: Self.voiceIdentifierKey) ?? ""
        if let raw = UserDefaults.standard.string(forKey: Self.ttsProviderKey),
           let p = TTSProvider(rawValue: raw) {
            ttsProvider = p
        }
        openAIVoice = UserDefaults.standard.string(forKey: Self.openAIVoiceKey) ?? OpenAITTSVoice.alloy.rawValue
        openAIModel = UserDefaults.standard.string(forKey: Self.openAIModelKey) ?? OpenAITTSModel.tts_1.rawValue
        openAIAPIKey = Keychain.get(KeychainKey.openAIAPIKey) ?? ""
        kokoroVoice = UserDefaults.standard.string(forKey: Self.kokoroVoiceKey) ?? KokoroVoice.defaultVoice.rawValue
    }

    /// Persist the OpenAI API key to Keychain. Called from the Settings view.
    func saveAPIKey() {
        if openAIAPIKey.isEmpty {
            Keychain.remove(KeychainKey.openAIAPIKey)
        } else {
            Keychain.set(openAIAPIKey, forKey: KeychainKey.openAIAPIKey)
        }
    }

    /// The voice to use for DJ speech. Falls back to the persona preset
    /// if the user hasn't picked one explicitly.
    var effectiveVoiceIdentifier: String {
        voiceIdentifier.isEmpty ? persona.voicePreset : voiceIdentifier
    }

    private func defaultSystemName() -> String {
        let full = NSFullUserName()
        return full.components(separatedBy: .whitespaces).first ?? full
    }
}

// MARK: - OPML Parser

private struct OPMLParser {
    static func parse(data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var urls: [String] = []
        // Simple regex-free extraction: find xmlUrl attributes
        let lines = xml.components(separatedBy: .newlines)
        for line in lines {
            if let range = line.range(of: "xmlUrl=\"") {
                let after = line[range.upperBound...]
                if let endRange = after.range(of: "\"") {
                    urls.append(String(after[after.startIndex..<endRange.lowerBound]))
                }
            }
        }
        return urls
    }
}
