import Foundation

/// Mirrors a curated set of UserDefaults keys to NSUbiquitousKeyValueStore
/// so the same preferences show up on the user's other signed-in devices.
///
/// Last-write-wins, 1 MB total cap — acceptable for settings + short RSS
/// feed URL lists. OpenAI API keys live in the Keychain and are explicitly
/// NOT synced here.
///
/// `CloudSyncService` is a thin one-way-then-one-way mirror: local writes
/// push to iCloud, remote `didChangeExternally` events push back into
/// UserDefaults and then post `.cloudSyncDidImportChanges` so the
/// `SettingsViewModel` can reload itself.
@MainActor
final class CloudSyncService {

    static let shared = CloudSyncService()

    /// Which UserDefaults keys participate in iCloud sync. Set via
    /// `register(keys:)` before the first `enable()` so the initial
    /// push/pull knows what to touch.
    private(set) var syncedKeys: Set<String> = []

    private let store = NSUbiquitousKeyValueStore.default
    private(set) var isEnabled: Bool = false

    private init() {
        // `note` isn't Sendable, so pull the keys out on the delivery queue
        // and only send the Sendable `[String]?` into the MainActor hop.
        // The service is a singleton and lives for the process lifetime, so
        // there's no deinit to tear the observer down.
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] note in
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            Task { @MainActor in self?.handleExternalChange(changedKeys: changedKeys) }
        }
    }

    // MARK: - Configuration

    func register(keys: Set<String>) {
        syncedKeys = keys
    }

    // MARK: - Enable / disable

    /// Turn on iCloud sync. Pushes current local values up, then pulls
    /// anything newer from the cloud into UserDefaults and fires the
    /// import notification so the VM refreshes.
    func enable() {
        isEnabled = true
        pushLocalValuesUp()
        pullCloudValuesDown(postNotification: true)
    }

    /// Turn off iCloud sync. Local UserDefaults are untouched; the cloud
    /// copy stays where it is and resumes diverging.
    func disable() {
        isEnabled = false
    }

    // MARK: - Write path (called from SettingsViewModel.saveToUserDefaults)

    /// Mirror a single value to iCloud if sync is enabled and the key is
    /// registered. Pass `nil` to remove. SettingsViewModel calls this from
    /// its existing save() pipeline so local-first behavior is preserved.
    func mirrorIfEnabled(key: String, value: Any?) {
        guard isEnabled, syncedKeys.contains(key) else { return }
        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    // MARK: - Private

    private func pushLocalValuesUp() {
        let defaults = UserDefaults.standard
        for key in syncedKeys {
            if let value = defaults.object(forKey: key) {
                store.set(value, forKey: key)
            }
        }
        store.synchronize()
    }

    private func pullCloudValuesDown(postNotification: Bool) {
        var didImport = false
        for key in syncedKeys {
            if let value = store.object(forKey: key) {
                UserDefaults.standard.set(value, forKey: key)
                didImport = true
            }
        }
        if didImport && postNotification {
            NotificationCenter.default.post(name: .cloudSyncDidImportChanges, object: nil)
        }
    }

    private func handleExternalChange(changedKeys: [String]?) {
        guard isEnabled else { return }
        guard let changedKeys else {
            // Some cases (quota, initial sync) omit the list; pull everything.
            pullCloudValuesDown(postNotification: true)
            return
        }
        var didImport = false
        for key in changedKeys where syncedKeys.contains(key) {
            if let value = store.object(forKey: key) {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            didImport = true
        }
        if didImport {
            NotificationCenter.default.post(name: .cloudSyncDidImportChanges, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted when NSUbiquitousKeyValueStore pushed new values down and
    /// CloudSyncService mirrored them into UserDefaults. SettingsViewModel
    /// listens and re-runs its load path.
    static let cloudSyncDidImportChanges = Notification.Name("cloudSyncDidImportChanges")
}
