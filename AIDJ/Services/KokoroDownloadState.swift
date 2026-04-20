import Foundation

/// Observable singleton for "what is Kokoro currently doing?" in the
/// MiniPlayerBar + Settings indicator. The actor that owns `KokoroTtsManager`
/// flips `mode` via `defer` around `initialize()` so every entry point —
/// lazy first-use render, Settings "Download Model" tap, post-removal
/// re-download, and launch-time warm-up — shows the same indicator
/// without divergence.
///
/// Two states are distinct because the user experience is very different:
/// a cold download is ~30 s on a slow connection; a cold load from cached
/// files is ~2-3 s of CoreML compile + warm-up. Showing the same string
/// for both would overstate one and understate the other.
@Observable
@MainActor
final class KokoroDownloadState {

    enum Mode: Equatable {
        case idle
        /// No cached model on disk — fetching from HuggingFace.
        case downloading
        /// Model files are cached; compiling the CoreML bundles + warming
        /// up + loading the vocab/lexicon. First-segment-after-launch hit.
        case loading

        var title: String {
            switch self {
            case .idle:        ""
            case .downloading: "Downloading DJ voice…"
            case .loading:     "Loading DJ voice…"
            }
        }

        var subtitle: String {
            switch self {
            case .idle:        ""
            case .downloading: "Kokoro model (~300 MB) • one time"
            case .loading:     "Warming up the voice model"
            }
        }
    }

    static let shared = KokoroDownloadState()

    private(set) var mode: Mode = .idle

    /// Convenience for bar-visibility gating — true whenever the spinner
    /// should be shown.
    var isActive: Bool { mode != .idle }

    private init() {}

    func begin(_ newMode: Mode) { mode = newMode }
    func end() { mode = .idle }
}
