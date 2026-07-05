import Foundation

/// Persona CRUD + JSON persistence, extracted out of `SettingsViewModel`.
/// Owned by `SettingsViewModel`, which exposes thin delegating members so
/// existing call sites (`PersonaListView`, `PersonaEditorView`, `RootView`)
/// don't need to change.
@Observable
@MainActor
final class PersonaStore {

    var customPersonas: [DJPersona] = []
    var activePersonaID: UUID = DJPersona.default.id

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Built-ins + user customs, in that order. Computed on demand.
    var allPersonas: [DJPersona] {
        DJPersona.builtIns + customPersonas
    }

    /// The active persona. Defaults to Alex if the active ID doesn't resolve.
    var persona: DJPersona {
        allPersonas.first(where: { $0.id == activePersonaID }) ?? .default
    }

    /// Reload from UserDefaults. Called by `SettingsViewModel` at init, after
    /// enabling iCloud sync, and on every `.cloudSyncDidImportChanges` import
    /// — all three need persona state re-pulled the same way the rest of
    /// settings does.
    func load() {
        if let data = defaults.data(forKey: SettingsKeys.customPersonas),
           let decoded = try? JSONDecoder().decode([DJPersona].self, from: data) {
            customPersonas = decoded
        }
        if let raw = defaults.string(forKey: SettingsKeys.activePersonaID),
           let uuid = UUID(uuidString: raw) {
            activePersonaID = uuid
        }
        migrateLegacyPersonaIfNeeded()
        // If the stored active ID no longer exists (deleted custom), fall back to default.
        if allPersonas.first(where: { $0.id == activePersonaID }) == nil {
            activePersonaID = DJPersona.default.id
        }
    }

    private func save() {
        let cloud = CloudSyncService.shared
        if let data = try? JSONEncoder().encode(customPersonas) {
            defaults.set(data, forKey: SettingsKeys.customPersonas)
            cloud.mirrorIfEnabled(key: SettingsKeys.customPersonas, value: data)
        }
        defaults.set(activePersonaID.uuidString, forKey: SettingsKeys.activePersonaID)
        cloud.mirrorIfEnabled(key: SettingsKeys.activePersonaID, value: activePersonaID.uuidString)
    }

    /// Activate a persona by ID. Triggers a save so the
    /// onChange(of: settings.persona) observer in RootView fires and hot-
    /// reloads the Producer.
    func setActivePersona(id: UUID) {
        activePersonaID = id
        save()
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
        save()
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
        save()
    }

    /// Remove a custom persona. Built-ins can't be deleted. If the deleted
    /// persona was active, activation falls back to `DJPersona.default`.
    func deleteCustomPersona(id: UUID) {
        guard let idx = customPersonas.firstIndex(where: { $0.id == id }) else { return }
        customPersonas.remove(at: idx)
        if activePersonaID == id {
            activePersonaID = DJPersona.default.id
        }
        save()
    }

    /// One-time migration: if Phase 1 stored a single persona under the old
    /// `djPersona` key AND its text differs from the built-in Alex, preserve
    /// it as a custom persona (with a fresh UUID so it's editable). If the
    /// text matches Alex exactly, just drop the legacy key — nothing to save.
    private func migrateLegacyPersonaIfNeeded() {
        guard let data = defaults.data(forKey: SettingsKeys.legacyPersona),
              let legacy = try? JSONDecoder().decode(DJPersona.self, from: data) else {
            return
        }
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
        defaults.removeObject(forKey: SettingsKeys.legacyPersona)
    }
}
