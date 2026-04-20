import SwiftUI

struct LibraryView: View {
    @State private var vm: LibraryViewModel
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?

    init(vm: LibraryViewModel) {
        self._vm = State(initialValue: vm)
    }

    var body: some View {
        List {
            if query.isEmpty {
                playlistsContent
            } else {
                searchContent
            }
        }
        .navigationTitle("Library")
        .searchable(text: $query, prompt: "Search playlists and songs")
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                await vm.performSearch(query: newValue)
            }
        }
        .task {
            await vm.loadPlaylists()
            await vm.loadRecentlyPlayed()
            await vm.loadRecommendations()
        }
        .refreshable {
            await vm.refreshLibrarySections()
        }
    }

    // MARK: - Browse (no query)

    @ViewBuilder
    private var playlistsContent: some View {
        if vm.isLoading && vm.playlists.isEmpty && vm.recentlyPlayed.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowSeparator(.hidden)
        } else if let error = vm.errorMessage, vm.playlists.isEmpty {
            ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
        } else {
            if !vm.recentlyPlayed.isEmpty {
                horizontalSection("Recently Played", items: vm.recentlyPlayed)
            }

            if !vm.recommendations.isEmpty {
                horizontalSection("Made for You", items: vm.recommendations)
            }

            if vm.playlists.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Add playlists in the Music app, then come back.")
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Your Playlists") {
                    ForEach(vm.playlists) { playlist in
                        playlistRow(playlist)
                    }
                }
            }
        }
    }

    private func horizontalSection(_ title: String, items: [LibraryItem]) -> some View {
        Section(title) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        cardWrapper(for: item)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowBackground(Color.clear)
        }
    }

    /// Playlists navigate to their detail view; tracks, albums, and
    /// stations play on tap. Stations start ApplicationMusicPlayer in
    /// radio mode, bypassing our Producer/Coordinator queue.
    @ViewBuilder
    private func cardWrapper(for item: LibraryItem) -> some View {
        switch item {
        case .playlist(let playlist):
            NavigationLink {
                PlaylistDetailView(playlist: playlist, vm: vm)
            } label: {
                LibraryCardView(item: item)
            }
            .buttonStyle(.plain)
        case .track, .album, .station:
            LibraryCardView(item: item)
                .onTapGesture {
                    Task { await vm.playLibraryItem(item) }
                }
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchContent: some View {
        let matchingPlaylists = vm.filteredPlaylists(matching: query)

        if matchingPlaylists.isEmpty && vm.searchResults.isEmpty && !vm.isSearching {
            ContentUnavailableView.search(text: query)
        } else {
            if !matchingPlaylists.isEmpty {
                Section("Playlists") {
                    ForEach(matchingPlaylists) { playlist in
                        playlistRow(playlist)
                    }
                }
            }

            if vm.isSearching && vm.searchResults.isEmpty {
                Section("Songs") {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                }
            } else if !vm.searchResults.isEmpty {
                Section("Songs") {
                    ForEach(vm.searchResults) { track in
                        songRow(track)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func playlistRow(_ playlist: PlaylistInfo) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                PlaylistDetailView(playlist: playlist, vm: vm)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                    Text(playlist.name)
                        .font(.body)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await vm.playPlaylist(playlist) }
            } label: {
                Image(systemName: "play.fill")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(playlist.name)")

            Button {
                Task { await vm.shufflePlaylist(playlist) }
            } label: {
                Image(systemName: "shuffle")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Shuffle \(playlist.name)")
        }
        .padding(.vertical, 4)
    }

    private func songRow(_ track: AIDJ.Track) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.body).lineLimit(1)
                Text(track.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Play") {
                Task { await vm.playSong(track) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
