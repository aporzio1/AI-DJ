import Testing
import Foundation
@testable import Patter

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {

    /// Matches `SettingsViewModel`'s private `openAIKeychainMigratedKey`.
    /// Pre-set to true so `loadFromUserDefaults` skips
    /// `Keychain.migrateToSynchronizable` mid-test — the remaining
    /// `Keychain.get` read is safe/nil on the test host.
    private static let openAIKeychainMigratedKey = "openAIKeychainMigratedToSynchronizable"

    private func makeSettings() -> SettingsViewModel {
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: Self.openAIKeychainMigratedKey)
        return SettingsViewModel(defaults: defaults)
    }

    // MARK: - Feed management

    @Test func addFeedAppendsValidURL() {
        let settings = makeSettings()
        settings.addFeed(urlString: "https://example.com/feed.xml")
        #expect(settings.feedURLStrings == ["https://example.com/feed.xml"])
    }

    @Test func addFeedRejectsEmptyString() {
        let settings = makeSettings()
        settings.addFeed(urlString: "")
        #expect(settings.feedURLStrings.isEmpty)
    }

    @Test func addFeedRejectsDuplicate() {
        let settings = makeSettings()
        settings.addFeed(urlString: "https://example.com/feed.xml")
        settings.addFeed(urlString: "https://example.com/feed.xml")
        #expect(settings.feedURLStrings.count == 1)
    }

    @Test func removeFeedAtOffset() {
        let settings = makeSettings()
        settings.addFeed(urlString: "https://a.example.com/feed.xml")
        settings.addFeed(urlString: "https://b.example.com/feed.xml")
        settings.removeFeed(at: IndexSet(integer: 0))
        #expect(settings.feedURLStrings == ["https://b.example.com/feed.xml"])
    }

    @Test func feedURLsComputedPropertyParsesValidStrings() {
        let settings = makeSettings()
        settings.addFeed(urlString: "https://example.com/feed.xml")
        #expect(settings.feedURLs == [URL(string: "https://example.com/feed.xml")!])
    }

    // MARK: - OPML import

    private func opml(urls: [String]) -> Data {
        let outlines = urls.map { "<outline xmlUrl=\"\($0)\" />" }.joined(separator: "\n")
        return """
        <?xml version="1.0"?>
        <opml version="1.0"><body>\(outlines)</body></opml>
        """.data(using: .utf8)!
    }

    @Test func importOPMLAddsNewFeeds() {
        let settings = makeSettings()
        settings.importOPML(data: opml(urls: ["https://a.example.com/feed.xml", "https://b.example.com/feed.xml"]))
        #expect(settings.feedURLStrings == ["https://a.example.com/feed.xml", "https://b.example.com/feed.xml"])
    }

    @Test func importOPMLDedupesAgainstExistingFeeds() {
        let settings = makeSettings()
        settings.addFeed(urlString: "https://a.example.com/feed.xml")
        settings.importOPML(data: opml(urls: ["https://a.example.com/feed.xml", "https://b.example.com/feed.xml"]))
        #expect(settings.feedURLStrings == ["https://a.example.com/feed.xml", "https://b.example.com/feed.xml"])
    }

    @Test func importOPMLDedupesWithinTheSameImport() {
        let settings = makeSettings()
        settings.importOPML(data: opml(urls: ["https://a.example.com/feed.xml", "https://a.example.com/feed.xml"]))
        #expect(settings.feedURLStrings == ["https://a.example.com/feed.xml"])
    }

    // MARK: - Persona CRUD

    @Test func addCustomPersonaActivatesByDefault() {
        let settings = makeSettings()
        let persona = settings.addCustomPersona(name: "Custom", styleDescriptor: "Custom style")
        #expect(settings.customPersonas.contains(persona))
        #expect(settings.activePersonaID == persona.id)
    }

    @Test func addCustomPersonaCanSkipActivation() {
        let settings = makeSettings()
        let originalActive = settings.activePersonaID
        _ = settings.addCustomPersona(name: "Custom", styleDescriptor: "Custom style", activate: false)
        #expect(settings.activePersonaID == originalActive)
    }

    @Test func duplicatePersonaAppendsCopySuffix() {
        let settings = makeSettings()
        let copy = settings.duplicatePersona(.alex)
        #expect(copy.name == "Alex Copy")
        #expect(copy.styleDescriptor == DJPersona.alex.styleDescriptor)
        #expect(copy.id != DJPersona.alex.id)
    }

    @Test func updateCustomPersonaChangesNameAndDescriptor() {
        let settings = makeSettings()
        let persona = settings.addCustomPersona(name: "Custom", styleDescriptor: "Original")
        settings.updateCustomPersona(id: persona.id, name: "Renamed", styleDescriptor: "Updated")

        let updated = settings.customPersonas.first { $0.id == persona.id }
        #expect(updated?.name == "Renamed")
        #expect(updated?.styleDescriptor == "Updated")
    }

    @Test func updateCustomPersonaNoOpsOnBuiltInID() {
        let settings = makeSettings()
        settings.updateCustomPersona(id: DJPersona.alex.id, name: "Hacked", styleDescriptor: "Hacked")
        #expect(settings.allPersonas.first { $0.id == DJPersona.alex.id }?.name == "Alex")
    }

    @Test func deleteCustomPersonaRemovesIt() {
        let settings = makeSettings()
        let persona = settings.addCustomPersona(name: "Custom", styleDescriptor: "Style", activate: false)
        settings.deleteCustomPersona(id: persona.id)
        #expect(!settings.customPersonas.contains(persona))
    }

    @Test func deletingActivePersonaFallsBackToDefault() {
        let settings = makeSettings()
        let persona = settings.addCustomPersona(name: "Custom", styleDescriptor: "Style")
        #expect(settings.activePersonaID == persona.id)

        settings.deleteCustomPersona(id: persona.id)
        #expect(settings.activePersonaID == DJPersona.default.id)
    }

    @Test func personaResolvesToDefaultWhenActiveIDIsUnresolvable() {
        let settings = makeSettings()
        settings.activePersonaID = UUID()
        #expect(settings.persona.id == DJPersona.default.id)
    }

    // MARK: - Legacy persona migration

    @Test func legacyPersonaMatchingAlexIsDroppedWithoutCreatingCustom() {
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: Self.openAIKeychainMigratedKey)
        let legacy = DJPersona.alex
        defaults.set(try! JSONEncoder().encode(legacy), forKey: "djPersona")

        let settings = SettingsViewModel(defaults: defaults)

        #expect(settings.customPersonas.isEmpty)
        #expect(defaults.data(forKey: "djPersona") == nil)
    }

    @Test func legacyPersonaDifferingFromAlexIsPreservedAsCustom() {
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: Self.openAIKeychainMigratedKey)
        let legacy = DJPersona(id: UUID(), name: "Old Persona", voicePreset: "voice-x", styleDescriptor: "Old style")
        defaults.set(try! JSONEncoder().encode(legacy), forKey: "djPersona")

        let settings = SettingsViewModel(defaults: defaults)

        #expect(settings.customPersonas.contains { $0.name == "Old Persona" && $0.styleDescriptor == "Old style" })
        #expect(settings.activePersonaID == settings.customPersonas.first { $0.name == "Old Persona" }?.id)
        #expect(defaults.data(forKey: "djPersona") == nil)
    }

    // MARK: - iOS 26 Kokoro downgrade (macOS no-op path)

    @Test func kokoroDowngradeIsANoOpOnMacOS() {
        // applyIOS26KokoroDowngradeIfNeeded is entirely #if os(iOS) — on
        // macOS it must leave the persisted provider untouched. The iOS
        // downgrade logic itself is smoke-tested on device, not unit-tested.
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: Self.openAIKeychainMigratedKey)
        defaults.set(TTSProvider.kokoro.rawValue, forKey: "ttsProvider")

        let settings = SettingsViewModel(defaults: defaults)

        #expect(settings.ttsProvider == .kokoro)
        #expect(!settings.showKokoroDowngradeNotice)
    }

    // MARK: - effectiveVoiceIdentifier

    @Test func effectiveVoiceIdentifierFallsBackToPersonaPresetWhenUnset() {
        let settings = makeSettings()
        settings.voiceIdentifier = ""
        #expect(settings.effectiveVoiceIdentifier == settings.persona.voicePreset)
    }

    @Test func effectiveVoiceIdentifierUsesExplicitSelectionWhenSet() {
        let settings = makeSettings()
        settings.voiceIdentifier = "com.apple.voice.premium.en-US.Zoe"
        #expect(settings.effectiveVoiceIdentifier == "com.apple.voice.premium.en-US.Zoe")
    }
}
