import SwiftUI

struct LibraryView: View {
    @State private var vm: LibraryViewModel

    init(vm: LibraryViewModel) {
        self._vm = State(initialValue: vm)
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView()
            } else if let error = vm.errorMessage {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else if vm.playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list",
                    description: Text("Add playlists in the Music app."))
            } else {
                playlistList
            }
        }
        .navigationTitle("Library")
        .task { await vm.loadPlaylists() }
    }

    private var playlistList: some View {
        List(vm.playlists) { playlist in
            HStack {
                VStack(alignment: .leading) {
                    Text(playlist.name).font(.body)
                }
                Spacer()
                Button("Play") {
                    Task { await vm.playPlaylist(playlist) }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
    }
}
