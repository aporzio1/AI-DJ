import SwiftUI
import MusicKit

struct MiniPlayerBar: View {
    let vm: NowPlayingViewModel
    let onTap: () -> Void

    var body: some View {
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

            playPauseButton
            skipButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 64)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { progressLine }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Progress

    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.quaternary)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 0.25), value: progress)
            }
        }
        .frame(height: 2)
    }

    private var progress: CGFloat {
        guard vm.duration > 0 else { return 0 }
        return CGFloat(min(1.0, max(0.0, vm.playbackTime / vm.duration)))
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
