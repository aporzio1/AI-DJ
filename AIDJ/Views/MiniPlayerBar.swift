import SwiftUI
import MusicKit

struct MiniPlayerBar: View {
    let vm: NowPlayingViewModel
    let onTap: () -> Void

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            topRow
            progressRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Row 1: artwork + title + transport

    private var topRow: some View {
        HStack(spacing: 12) {
            artworkThumb

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if vm.isDJSpeaking {
                Image(systemName: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("DJ speaking")
            }

            thumbsDownButton
            thumbsUpButton
            playPauseButton
            skipButton
        }
        .frame(minHeight: 48)
    }

    // MARK: - Thumbs

    private var canRateCurrent: Bool {
        if case .track = vm.currentItem { return true }
        return false
    }

    private var thumbsDownButton: some View {
        Button {
            vm.rateCurrentTrack(.down)
        } label: {
            Image(systemName: vm.currentFeedback == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(vm.currentFeedback == .down ? Color.red : .secondary)
        .disabled(!canRateCurrent)
        .accessibilityLabel("Thumbs down")
    }

    private var thumbsUpButton: some View {
        Button {
            vm.rateCurrentTrack(.up)
        } label: {
            Image(systemName: vm.currentFeedback == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(vm.currentFeedback == .up ? Color.green : .secondary)
        .disabled(!canRateCurrent)
        .accessibilityLabel("Thumbs up")
    }

    // MARK: - Row 2: scrubbable progress with time labels

    @ViewBuilder
    private var progressRow: some View {
        HStack(spacing: 8) {
            shuffleButton

            if vm.duration > 0 {
                Text(formatTime(displayedTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)

                Slider(
                    value: $scrubValue,
                    in: 0...max(vm.duration, 0.1),
                    onEditingChanged: handleScrubEditingChanged
                )
                // Don't propagate taps on the slider track to the row's onTapGesture.
                .onTapGesture { }

                Text("-" + formatTime(max(vm.duration - displayedTime, 0)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
            }

            repeatButton
        }
        .onAppear { scrubValue = vm.playbackTime }
        .onChange(of: vm.playbackTime) { _, newValue in
            // Poller updates — only accept when user isn't actively dragging.
            if !isScrubbing { scrubValue = newValue }
        }
    }

    // MARK: - Shuffle / Repeat

    private var shuffleButton: some View {
        Button {
            vm.shuffleUpcoming()
        } label: {
            Image(systemName: "shuffle")
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Shuffle upcoming")
    }

    private var repeatButton: some View {
        Button {
            vm.cycleRepeatMode()
        } label: {
            Image(systemName: vm.repeatMode.systemImage)
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(vm.repeatMode.isActive ? Color.accentColor : .secondary)
        .accessibilityLabel(vm.repeatMode.accessibilityLabel)
    }

    private var displayedTime: TimeInterval {
        isScrubbing ? scrubValue : vm.playbackTime
    }

    private func handleScrubEditingChanged(_ editing: Bool) {
        if editing {
            scrubValue = vm.playbackTime
            isScrubbing = true
        } else {
            vm.seek(to: scrubValue)
            isScrubbing = false
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var artworkThumb: some View {
        Group {
            if let art = vm.currentArtwork {
                ArtworkImage(art, width: 44, height: 44)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var playPauseButton: some View {
        Button {
            if vm.playbackState == .playing { vm.pause() } else { vm.play() }
        } label: {
            Image(systemName: vm.playbackState == .playing ? "pause.fill" : "play.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vm.playbackState == .playing ? "Pause" : "Play")
    }

    private var skipButton: some View {
        Button {
            vm.skip()
        } label: {
            Image(systemName: "forward.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip")
    }

    // MARK: - Text

    private var title: String {
        switch vm.currentItem {
        case .track(let t):     return t.title
        case .djSegment:        return "DJ"
        case nil:               return "Nothing Playing"
        }
    }

    private var subtitle: String {
        switch vm.currentItem {
        case .track(let t):     return t.artist
        case .djSegment(let s): return s.kind.rawValue.capitalized
        case nil:               return ""
        }
    }
}
