import SwiftUI

struct PlaylistDetailView: View {
    let playlist: PlaylistInfo
    @State private var vm: LibraryViewModel

    init(playlist: PlaylistInfo, vm: LibraryViewModel) {
        self.playlist = playlist
        self._vm = State(initialValue: vm)
    }

    var body: some View {
        List {
            headerSection
            songsSection
        }
        .navigationTitle(playlist.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task { await vm.selectPlaylist(playlist) }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, height: 120)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(playlist.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Button {
                        Task { await vm.playPlaylist(playlist) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await vm.shufflePlaylist(playlist) }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Songs

    @ViewBuilder
    private var songsSection: some View {
        if vm.isLoading && vm.songs.isEmpty {
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        } else if vm.songs.isEmpty {
            Section {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("This playlist looks empty.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        } else {
            Section("Songs") {
                ForEach(Array(vm.songs.enumerated()), id: \.element.id) { index, track in
                    songRow(track, index: index + 1)
                }
            }
        }
    }

    private func songRow(_ track: Patter.Track, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.body).lineLimit(1)
                Text(track.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                Task { await vm.playSong(track) }
            } label: {
                Image(systemName: "play.fill")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(track.title)")
        }
        .padding(.vertical, 4)
    }
}
