import SwiftUI

struct SettingsView: View {
    @State private var vm: SettingsViewModel
    @State private var newFeedURL = ""
    @State private var showingOPMLImporter = false

    init(vm: SettingsViewModel) {
        self._vm = State(initialValue: vm)
    }

    var body: some View {
        Form {
            djSection
            newsSection
            feedsSection
        }
        .navigationTitle("Settings")
#if os(macOS)
        .fileImporter(isPresented: $showingOPMLImporter,
                      allowedContentTypes: [.xml, .data],
                      onCompletion: importOPML)
#endif
    }

    private var djSection: some View {
        Section("DJ") {
            Toggle("Enable DJ", isOn: $vm.djEnabled)
            Toggle("Announcements", isOn: $vm.announcementsEnabled)
                .disabled(!vm.djEnabled)

            LabeledContent("Persona") {
                Text(vm.persona.name)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Your Name") {
                TextField("Your name", text: $vm.listenerName, onCommit: { vm.save() })
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
        }
    }

    private var newsSection: some View {
        Section("News") {
            Toggle("Include news headlines", isOn: $vm.newsEnabled)
                .disabled(!vm.djEnabled)
        }
    }

    private var feedsSection: some View {
        Section("RSS Feeds") {
            ForEach(vm.feedURLStrings, id: \.self) { url in
                Text(url).font(.caption).foregroundStyle(.secondary)
            }
            .onDelete { vm.removeFeed(at: $0) }

            HStack {
                TextField("https://example.com/feed.xml", text: $newFeedURL)
                    .textFieldStyle(.plain)
                    .font(.caption)
#if os(iOS)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
#endif
                Button("Add") {
                    vm.addFeed(urlString: newFeedURL)
                    newFeedURL = ""
                }
                .disabled(newFeedURL.isEmpty)
            }

#if os(macOS)
            Button("Import OPML…") { showingOPMLImporter = true }
#endif
        }
    }

#if os(macOS)
    private func importOPML(_ result: Result<URL, Error>) {
        guard case .success(let url) = result,
              let data = try? Data(contentsOf: url) else { return }
        vm.importOPML(data: data)
    }
#endif
}
