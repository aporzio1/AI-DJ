import Foundation

/// Observable singleton for "is the Kokoro model currently downloading /
/// compiling?" The actor that owns `KokoroTtsManager` flips `isDownloading`
/// via `defer` around `initialize()` so every entry point — lazy first-use
/// render, Settings "Download Model" tap, post-removal re-download — shows
/// the same indicator without divergence.
///
/// FluidAudio v0.13.5 exposes no download-progress callback, so this is
/// indeterminate. Real % progress is logged as a backlog item pending an
/// upstream API (see tracker K9).
@Observable
@MainActor
final class KokoroDownloadState {
    static let shared = KokoroDownloadState()

    private(set) var isDownloading: Bool = false

    private init() {}

    func begin() { isDownloading = true }
    func end()   { isDownloading = false }
}
