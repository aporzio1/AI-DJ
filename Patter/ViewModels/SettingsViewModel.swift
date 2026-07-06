import Foundation

@Observable
@MainActor
final class SettingsViewModel {

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

    /// Set when init() force-flips a persisted `.kokoro` selection to `.system`
    /// on iOS 26 to dodge the libBNNS+SME2 conv-transpose-1D segfault (K6).
    /// RootView observes this and shows a one-time alert; SwiftUI clears it
    /// back to false on dismissal.
    var showKokoroDowngradeNotice: Bool = false

    private let defaults: UserDefaults
    private let personaStore: PersonaStore

    /// Keys that participate in iCloud sync. Kept deliberately narrow:
    /// feed URLs, preferences, and persona library — but NOT the
    /// iCloudSyncEnabled flag itself (device-local decision), the OpenAI
    /// API key (Keychain), or legacy/transient keys.
    static let syncedKeys: Set<String> = [
        SettingsKeys.feeds,
        SettingsKeys.djEnabled,
        SettingsKeys.djFrequency,
        SettingsKeys.newsEnabled,
        SettingsKeys.newsFrequency,
        SettingsKeys.listenerName,
        SettingsKeys.voiceIdentifier,
        SettingsKeys.ttsProvider,
        SettingsKeys.openAIVoice,
        SettingsKeys.openAIModel,
        SettingsKeys.kokoroVoice,
        SettingsKeys.customPersonas,
        SettingsKeys.activePersonaID
    ]

    /// Soft cap on user-edited prompt instructions. Longer descriptors tend to
    /// pull the DJ off-topic; the editor enforces this in UI.
    static let maxStyleDescriptorLength = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.personaStore = PersonaStore(defaults: defaults)
        loadFromUserDefaults()
        CloudSyncService.shared.register(keys: Self.syncedKeys)
        if iCloudSyncEnabled {
            CloudSyncService.shared.enable()
            // Re-load AFTER enabling so a fresh device pulls cloud values
            // down before we hand the VM to RootView.
            loadFromUserDefaults()
        }
        applyIOS26KokoroDowngradeIfNeeded()
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
        guard OPMLParser.isValidFeedURL(urlString) else { return }
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
        defaults.set(enabled, forKey: SettingsKeys.iCloudSyncEnabled)
        if enabled {
            CloudSyncService.shared.enable()
            // Re-read defaults in case the enable() pulled newer values down.
            loadFromUserDefaults()
        } else {
            CloudSyncService.shared.disable()
        }
    }

    private func saveToUserDefaults() {
        let cloud = CloudSyncService.shared

        func write(_ value: Any?, forKey key: String) {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            cloud.mirrorIfEnabled(key: key, value: value)
        }

        write(feedURLStrings, forKey: SettingsKeys.feeds)
        write(djEnabled, forKey: SettingsKeys.djEnabled)
        write(djFrequency.rawValue, forKey: SettingsKeys.djFrequency)
        write(newsEnabled, forKey: SettingsKeys.newsEnabled)
        write(newsFrequency.rawValue, forKey: SettingsKeys.newsFrequency)
        write(listenerName, forKey: SettingsKeys.listenerName)
        write(voiceIdentifier, forKey: SettingsKeys.voiceIdentifier)
        write(ttsProvider.rawValue, forKey: SettingsKeys.ttsProvider)
        write(openAIVoice, forKey: SettingsKeys.openAIVoice)
        write(openAIModel, forKey: SettingsKeys.openAIModel)
        write(kokoroVoice, forKey: SettingsKeys.kokoroVoice)
        // Persona state is persisted by PersonaStore itself.
        // iCloudSyncEnabled is a device-local decision; never mirror it.
        defaults.set(iCloudSyncEnabled, forKey: SettingsKeys.iCloudSyncEnabled)
        // API key is persisted to Keychain via saveAPIKey(); not echoed to UserDefaults.
    }

    private func loadFromUserDefaults() {
        iCloudSyncEnabled = defaults.object(forKey: SettingsKeys.iCloudSyncEnabled) as? Bool ?? false
        feedURLStrings = defaults.stringArray(forKey: SettingsKeys.feeds) ?? []
        djEnabled = defaults.object(forKey: SettingsKeys.djEnabled) as? Bool ?? true
        if let raw = defaults.string(forKey: SettingsKeys.djFrequency),
           let freq = DJFrequency(rawValue: raw) {
            djFrequency = freq
        }
        newsEnabled = defaults.object(forKey: SettingsKeys.newsEnabled) as? Bool ?? true
        if let raw = defaults.string(forKey: SettingsKeys.newsFrequency),
           let freq = NewsFrequency(rawValue: raw) {
            newsFrequency = freq
        }
        if let stored = defaults.string(forKey: SettingsKeys.listenerName), !stored.isEmpty {
            listenerName = stored
        } else {
            listenerName = defaultSystemName()
        }
        voiceIdentifier = defaults.string(forKey: SettingsKeys.voiceIdentifier) ?? ""
        if let raw = defaults.string(forKey: SettingsKeys.ttsProvider),
           let p = TTSProvider(rawValue: raw) {
            ttsProvider = p
        }
        openAIVoice = defaults.string(forKey: SettingsKeys.openAIVoice) ?? OpenAITTSVoice.alloy.rawValue
        openAIModel = defaults.string(forKey: SettingsKeys.openAIModel) ?? OpenAITTSModel.tts_1.rawValue
        // `loadFromUserDefaults` runs on every iCloud sync import, not just init.
        // Without the sentinel the Keychain rewrite would re-fire per import batch.
        if !defaults.bool(forKey: SettingsKeys.openAIKeychainMigrated) {
            Keychain.migrateToSynchronizable(KeychainKey.openAIAPIKey)
            defaults.set(true, forKey: SettingsKeys.openAIKeychainMigrated)
        }
        openAIAPIKey = Keychain.get(KeychainKey.openAIAPIKey) ?? ""
        // Clamp persisted selections to voices that have a published
        // KokoroAne voice pack — see KokoroVoice.available.
        let storedKokoroVoice = defaults.string(forKey: SettingsKeys.kokoroVoice) ?? KokoroVoice.defaultVoice.rawValue
        kokoroVoice = KokoroVoice.available.map(\.rawValue).contains(storedKokoroVoice)
            ? storedKokoroVoice
            : KokoroVoice.defaultVoice.rawValue
        personaStore.load()
    }

    /// On iOS 26+, FluidAudio's Kokoro CoreML model triggers a hard crash
    /// during model load (tracker K6/K24: iOS 26 segfaults inside
    /// libBNNS.dylib's SME2 1D-conv-transpose kernel; iOS 27 hits a different
    /// but equally fatal MPSGraph/MLIR compile assertion — same underlying
    /// "Kokoro's CoreML graph doesn't survive Apple's on-device ML stack on
    /// this OS" problem, confirmed non-fixed across at least two major
    /// versions). The crash is in Apple framework code so the in-app
    /// `try/catch` fallback in DJVoiceRouter can't catch it — the process is
    /// dead (or hung) before the fallback runs. So if the persisted provider
    /// is `.kokoro` on iOS 26 or later, force-flip it to `.system` once and
    /// surface a notice. `>=` rather than `==` — there's no evidence a future
    /// major version fixes this without a FluidAudio update, and `==` left
    /// iOS 27 completely unguarded (reproduced as an app hang). The sentinel
    /// is per-device and one-shot: if the user re-enables Kokoro afterwards
    /// we respect their choice and don't fight them.
    private func applyIOS26KokoroDowngradeIfNeeded() {
        #if os(iOS)
        // SPIKE (kokoro-ane-0.15.4): downgrade disabled on this branch so the
        // KokoroAne backend can be device-tested on iOS 26+ (Backlog #12).
        // Restore before merge if the device gates fail.
        return
        #elseif os(iOS)
        let alreadyDowngraded = defaults.bool(forKey: SettingsKeys.kokoroDowngradedFromIOS26)
        guard !alreadyDowngraded,
              ttsProvider == .kokoro,
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
        else { return }

        Log.app.warning("Auto-downgrading TTS provider .kokoro → .system on iOS 26+ (tracker K6/K24)")
        ttsProvider = .system
        defaults.set(true, forKey: SettingsKeys.kokoroDowngradedFromIOS26)
        defaults.set(ttsProvider.rawValue, forKey: SettingsKeys.ttsProvider)
        showKokoroDowngradeNotice = true
        #endif
    }

    // MARK: Persona
    //
    // Thin delegates to PersonaStore so PersonaListView/PersonaEditorView/
    // RootView call sites don't churn — see PersonaStore.swift for the
    // actual CRUD + persistence logic.

    var customPersonas: [DJPersona] {
        get { personaStore.customPersonas }
        set { personaStore.customPersonas = newValue }
    }

    var activePersonaID: UUID {
        get { personaStore.activePersonaID }
        set { personaStore.activePersonaID = newValue }
    }

    var allPersonas: [DJPersona] { personaStore.allPersonas }
    var persona: DJPersona { personaStore.persona }

    func setActivePersona(id: UUID) {
        personaStore.setActivePersona(id: id)
    }

    @discardableResult
    func addCustomPersona(name: String, styleDescriptor: String, activate: Bool = true) -> DJPersona {
        personaStore.addCustomPersona(name: name, styleDescriptor: styleDescriptor, activate: activate)
    }

    @discardableResult
    func duplicatePersona(_ source: DJPersona, activate: Bool = true) -> DJPersona {
        personaStore.duplicatePersona(source, activate: activate)
    }

    func updateCustomPersona(id: UUID, name: String, styleDescriptor: String) {
        personaStore.updateCustomPersona(id: id, name: name, styleDescriptor: styleDescriptor)
    }

    func deleteCustomPersona(id: UUID) {
        personaStore.deleteCustomPersona(id: id)
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
