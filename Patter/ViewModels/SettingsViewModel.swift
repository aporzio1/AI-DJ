import Foundation

@Observable
@MainActor
final class SettingsViewModel {

    var customPersonas: [DJPersona] = []
    var activePersonaID: UUID = DJPersona.default.id
    var iCloudSyncEnabled: Bool = false
    var djEnabled: Bool = true
    var djFrequency: DJFrequency = .default
    var newsEnabled: Bool = true
    var newsFrequency: NewsFrequency = .default
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
    private static let djFrequencyKey = "djFrequency"
    private static let newsEnabledKey = "newsEnabled"
    private static let newsFrequencyKey = "newsFrequency"
    private static let listenerNameKey = "listenerName"
    private static let voiceIdentifierKey = "voiceIdentifier"
    private static let ttsProviderKey = "ttsProvider"
    private static let openAIVoiceKey = "openAIVoice"
    private static let openAIModelKey = "openAIModel"
    private static let kokoroVoiceKey = "kokoroVoice"
    private static let legacyPersonaKey = "djPersona"         // Phase 1 single-persona storage
    private static let customPersonasKey = "djCustomPersonas"
    private static let activePersonaIDKey = "djActivePersonaID"
    private static let iCloudSyncEnabledKey = "iCloudSyncEnabled"   // device-local, NOT synced

    /// Keys that participate in iCloud sync. Kept deliberately narrow:
    /// feed URLs, preferences, and persona library — but NOT the
    /// iCloudSyncEnabled flag itself (device-local decision), the OpenAI
    /// API key (Keychain), or legacy/transient keys.
    static let syncedKeys: Set<String> = [
        feedsKey,
        djEnabledKey,
        djFrequencyKey,
        newsEnabledKey,
        newsFrequencyKey,
        listenerNameKey,
        voiceIdentifierKey,
        ttsProviderKey,
        openAIVoiceKey,
        openAIModelKey,
        kokoroVoiceKey,
        customPersonasKey,
        activePersonaIDKey
    ]

    /// Soft cap on user-edited prompt instructions. Longer descriptors tend to
    /// pull the DJ off-topic; the editor enforces this in UI.
    static let maxStyleDescriptorLength = 500

    init() {
        loadFromUserDefaults()
        CloudSyncService.shared.register(keys: Self.syncedKeys)
        if iCloudSyncEnabled {
            CloudSyncService.shared.enable()
            // Re-load AFTER enabling so a fresh device pulls cloud values
            // down before we hand the VM to RootView.
            loadFromUserDefaults()
        }
        // The SettingsViewModel is owned by PatterApp for the whole process
        // lifetime, so we deliberately don't track + remove the observer on
        // deinit — Swift 6 nonisolated-deinit rules around @Observable make
        // that awkward and there's no real churn to clean up.
        NotificationCenter.default.addObserver(
            forName: .cloudSyncDidImportChanges,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.loadFromUserDefaults() }
        }
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

    /// Enable or disable iCloud sync. Flipping ON pushes local values to
    /// the cloud and pulls back anything newer; flipping OFF just stops
    /// listening — the cloud copy stays where it is.
    func setiCloudSyncEnabled(_ enabled: Bool) {
        guard enabled != iCloudSyncEnabled else { return }
        iCloudSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.iCloudSyncEnabledKey)
        if enabled {
            CloudSyncService.shared.enable()
            // Re-read defaults in case the enable() pulled newer values down.
            loadFromUserDefaults()
        } else {
            CloudSyncService.shared.disable()
        }
    }

    private func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        let cloud = CloudSyncService.shared

        func write(_ value: Any?, forKey key: String) {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            cloud.mirrorIfEnabled(key: key, value: value)
        }

        write(feedURLStrings, forKey: Self.feedsKey)
        write(djEnabled, forKey: Self.djEnabledKey)
        write(djFrequency.rawValue, forKey: Self.djFrequencyKey)
        write(newsEnabled, forKey: Self.newsEnabledKey)
        write(newsFrequency.rawValue, forKey: Self.newsFrequencyKey)
        write(listenerName, forKey: Self.listenerNameKey)
        write(voiceIdentifier, forKey: Self.voiceIdentifierKey)
        write(ttsProvider.rawValue, forKey: Self.ttsProviderKey)
        write(openAIVoice, forKey: Self.openAIVoiceKey)
        write(openAIModel, forKey: Self.openAIModelKey)
        write(kokoroVoice, forKey: Self.kokoroVoiceKey)
        if let data = try? JSONEncoder().encode(customPersonas) {
            write(data, forKey: Self.customPersonasKey)
        }
        write(activePersonaID.uuidString, forKey: Self.activePersonaIDKey)
        // iCloudSyncEnabled is a device-local decision; never mirror it.
        defaults.set(iCloudSyncEnabled, forKey: Self.iCloudSyncEnabledKey)
        // API key is persisted to Keychain via saveAPIKey(); not echoed to UserDefaults.
    }

    private func loadFromUserDefaults() {
        iCloudSyncEnabled = UserDefaults.standard.object(forKey: Self.iCloudSyncEnabledKey) as? Bool ?? false
        feedURLStrings = UserDefaults.standard.stringArray(forKey: Self.feedsKey) ?? []
        djEnabled = UserDefaults.standard.object(forKey: Self.djEnabledKey) as? Bool ?? true
        if let raw = UserDefaults.standard.string(forKey: Self.djFrequencyKey),
           let freq = DJFrequency(rawValue: raw) {
            djFrequency = freq
        }
        newsEnabled = UserDefaults.standard.object(forKey: Self.newsEnabledKey) as? Bool ?? true
        if let raw = UserDefaults.standard.string(forKey: Self.newsFrequencyKey),
           let freq = NewsFrequency(rawValue: raw) {
            newsFrequency = freq
        }
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
        // Phase 2: load the custom persona list and the active-ID pointer.
        if let data = UserDefaults.standard.data(forKey: Self.customPersonasKey),
           let decoded = try? JSONDecoder().decode([DJPersona].self, from: data) {
            customPersonas = decoded
        }
        if let raw = UserDefaults.standard.string(forKey: Self.activePersonaIDKey),
           let uuid = UUID(uuidString: raw) {
            activePersonaID = uuid
        }
        migrateLegacyPersonaIfNeeded()
        // If the stored active ID no longer exists (deleted custom), fall back to default.
        if allPersonas.first(where: { $0.id == activePersonaID }) == nil {
            activePersonaID = DJPersona.default.id
        }
    }

    // MARK: Persona

    /// Built-ins + user customs, in that order. Computed on demand.
    var allPersonas: [DJPersona] {
        DJPersona.builtIns + customPersonas
    }

    /// The active persona. Defaults to Alex if the active ID doesn't resolve.
    var persona: DJPersona {
        allPersonas.first(where: { $0.id == activePersonaID }) ?? .default
    }

    /// Activate a persona by ID. Triggers the UserDefaults save so the
    /// onChange(of: settings.persona) observer in RootView fires and hot-
    /// reloads the Producer.
    func setActivePersona(id: UUID) {
        activePersonaID = id
        saveToUserDefaults()
    }

    /// Create a new custom persona and return it. If `activate` is true (the
    /// default), the new persona becomes active immediately.
    @discardableResult
    func addCustomPersona(name: String, styleDescriptor: String, activate: Bool = true) -> DJPersona {
        let persona = DJPersona(
            id: UUID(),
            name: name,
            voicePreset: DJPersona.default.voicePreset,
            styleDescriptor: styleDescriptor
        )
        customPersonas.append(persona)
        if activate { activePersonaID = persona.id }
        saveToUserDefaults()
        return persona
    }

    /// Duplicate a built-in (or any persona) as a new editable custom copy.
    /// Appends " Copy" to the name so the source is easy to spot.
    @discardableResult
    func duplicatePersona(_ source: DJPersona, activate: Bool = true) -> DJPersona {
        addCustomPersona(
            name: source.name + " Copy",
            styleDescriptor: source.styleDescriptor,
            activate: activate
        )
    }

    /// Edit an existing custom persona. Silently no-ops on built-in IDs —
    /// the editor never opens for those.
    func updateCustomPersona(id: UUID, name: String, styleDescriptor: String) {
        guard let idx = customPersonas.firstIndex(where: { $0.id == id }) else { return }
        let existing = customPersonas[idx]
        customPersonas[idx] = DJPersona(
            id: existing.id,
            name: name,
            voicePreset: existing.voicePreset,
            styleDescriptor: styleDescriptor
        )
        saveToUserDefaults()
    }

    /// Remove a custom persona. Built-ins can't be deleted. If the deleted
    /// persona was active, activation falls back to `DJPersona.default`.
    func deleteCustomPersona(id: UUID) {
        guard let idx = customPersonas.firstIndex(where: { $0.id == id }) else { return }
        customPersonas.remove(at: idx)
        if activePersonaID == id {
            activePersonaID = DJPersona.default.id
        }
        saveToUserDefaults()
    }

    /// One-time migration: if Phase 1 stored a single persona under the old
    /// `djPersona` key AND its text differs from the built-in Alex, preserve
    /// it as a custom persona (with a fresh UUID so it's editable). If the
    /// text matches Alex exactly, just drop the legacy key — nothing to save.
    private func migrateLegacyPersonaIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyPersonaKey),
              let legacy = try? JSONDecoder().decode(DJPersona.self, from: data) else {
            return
        }
        let defaults = UserDefaults.standard
        let alex = DJPersona.alex
        let isUnchanged = legacy.name == alex.name
            && legacy.styleDescriptor == alex.styleDescriptor
        if !isUnchanged {
            let preserved = DJPersona(
                id: UUID(),
                name: legacy.name,
                voicePreset: legacy.voicePreset,
                styleDescriptor: legacy.styleDescriptor
            )
            customPersonas.append(preserved)
            activePersonaID = preserved.id
        }
        defaults.removeObject(forKey: Self.legacyPersonaKey)
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
