import Foundation

/// Formats a `TimeInterval` as `m:ss` for transport UI (MiniPlayerBar,
/// NowPlayingView). Negative or non-finite values render as "0:00".
func formatPlaybackTime(_ time: TimeInterval) -> String {
    guard time.isFinite, time >= 0 else { return "0:00" }
    let total = Int(time)
    return String(format: "%d:%02d", total / 60, total % 60)
}
