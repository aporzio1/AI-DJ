import SwiftUI
import MusicKit

struct NowPlayingView: View {
    @State private var vm: NowPlayingViewModel
    @State private var scrubTime: Double?

    init(vm: NowPlayingViewModel) {
        self._vm = State(initialValue: vm)
    }

    var body: some View {
        VStack(spacing: 24) {
            artworkView
            infoView
            if vm.isDJSpeaking {
                djBanner
            }
            progressSlider
            transportControls
        }
        .padding()
        .onAppear { vm.startObserving() }
        .onDisappear { vm.stopObserving() }
    }

    private var progressSlider: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubTime ?? vm.playbackTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(vm.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let t = scrubTime {
                        vm.seek(to: t)
                        scrubTime = nil
                    }
                }
            )
            .disabled(vm.duration <= 0)
            HStack {
                Text(format(scrubTime ?? vm.playbackTime))
                Spacer()
                Text("-\(format(max(vm.duration - (scrubTime ?? vm.playbackTime), 0)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 320)
    }

    private func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private var artworkView: some View {
        Group {
            if let artwork = vm.currentArtwork {
                ArtworkImage(artwork, width: 260, height: 260)
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 260, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var artworkPlaceholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }

    private var infoView: some View {
        VStack(spacing: 4) {
            Text(currentTitle)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(currentSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var currentTitle: String {
        switch vm.currentItem {
        case .track(let t):     return t.title
        case .djSegment:        return "DJ"
        case nil:               return "Nothing Playing"
        }
    }

    private var currentSubtitle: String {
        switch vm.currentItem {
        case .track(let t):     return "\(t.artist) — \(t.album)"
        case .djSegment(let s): return s.kind.rawValue.capitalized
        case nil:               return ""
        }
    }

    private var djBanner: some View {
        HStack(spacing: 8) {
            Label("DJ is speaking…", systemImage: "waveform")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())

            Button {
                vm.regenerateDJ()
            } label: {
                if vm.isRegenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderless)
            .disabled(vm.isRegenerating)
            .help("Generate a different DJ take for this transition")
        }
    }

    private var transportControls: some View {
        HStack(spacing: 32) {
            Button { vm.previous() } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            Button {
                if vm.playbackState == .playing {
                    vm.pause()
                } else {
                    vm.play()
                }
            } label: {
                Image(systemName: vm.playbackState == .playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
            }
            Button { vm.skip() } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
        }
        .buttonStyle(.plain)
    }
}
