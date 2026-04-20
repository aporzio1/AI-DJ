import SwiftUI
@preconcurrency import MusicKit

/// Horizontal-scroll card used in Library sections like Recently Played
/// and (later) Recommendations. Renders whichever artwork the item carries
/// and falls back to an SF Symbol when none resolves.
struct LibraryCardView: View {
    let item: LibraryItem
    let artwork: ProviderArtwork?
    let size: CGFloat

    init(item: LibraryItem, artwork: ProviderArtwork? = nil, size: CGFloat = 140) {
        self.item = item
        self.artwork = artwork
        self.size = size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderArtworkView(
                artwork: artwork,
                fallbackURL: item.fallbackArtworkURL,
                placeholderSystemImage: item.placeholderSystemImage,
                size: size
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(item.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: size, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Renders a ProviderArtwork, with an optional plain URL fallback and an
/// SF Symbol placeholder. Used by Library cards; call sites that already
/// hold a MusicKit.Artwork directly (e.g. NowPlayingView) don't need this yet.
struct ProviderArtworkView: View {
    let artwork: ProviderArtwork?
    let fallbackURL: URL?
    let placeholderSystemImage: String
    let size: CGFloat

    var body: some View {
        switch artwork {
        case .musicKit(let art):
            ArtworkImage(art, width: size, height: size)
        case .url(let url):
            asyncImage(url: url)
        case .none:
            if let url = fallbackURL {
                asyncImage(url: url)
            } else {
                placeholder
            }
        }
    }

    @ViewBuilder
    private func asyncImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay(ProgressView().scaleEffect(0.7))
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: placeholderSystemImage)
                .font(.system(size: size * 0.35))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }
}
