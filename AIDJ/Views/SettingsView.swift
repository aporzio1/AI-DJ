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
            if vm.djEnabled && vm.newsEnabled {
                feedsSection
#if os(macOS)
                opmlSection
#endif
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
#if os(macOS)
        .fileImporter(isPresented: $showingOPMLImporter,
                      allowedContentTypes: [.xml, .data],
                      onCompletion: importOPML)
#endif
    }

    // MARK: - DJ

    private var djSection: some View {
        Section {
            Toggle("Enable DJ", isOn: $vm.djEnabled)

            HStack {
                Text("Your Name")
                Spacer(minLength: 16)
                TextField("", text: $vm.listenerName)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 240)
                    .onChange(of: vm.listenerName) { _, _ in vm.save() }
            }

            LabeledContent("Persona") {
                Text(vm.persona.name).foregroundStyle(.secondary)
            }
        } header: {
            Text("DJ")
        } footer: {
            Text("The DJ introduces tracks and adds commentary between songs. Your name may be used occasionally to personalize greetings.")
        }
    }

    // MARK: - News

    private var newsSection: some View {
        Section {
            Toggle("Include News Headlines", isOn: $vm.newsEnabled)
                .disabled(!vm.djEnabled)
        } header: {
            Text("News")
        } footer: {
            Text("When enabled, the DJ may reference recent headlines from your RSS feeds.")
        }
    }

    // MARK: - RSS Feeds

    private var feedsSection: some View {
        Section {
            if vm.feedURLStrings.isEmpty {
                ContentUnavailableView {
                    Label("No Feeds", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Add a feed URL below to pull in recent headlines.")
                }
                .padding(.vertical, 12)
            } else {
                ForEach(vm.feedURLStrings, id: \.self) { url in
                    feedRow(url)
                }
                .onDelete { vm.removeFeed(at: $0) }
            }

            addFeedRow
        } header: {
            Text("RSS Feeds")
        } footer: {
            Text("Feeds are fetched periodically and the most recent headlines are offered to the DJ.")
        }
    }

    private func feedRow(_ urlString: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hostName(for: urlString))
                .font(.body)
            Text(urlString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }

    private var addFeedRow: some View {
        HStack(spacing: 12) {
            TextField("https://example.com/feed.xml", text: $newFeedURL)
                .textFieldStyle(.plain)
#if os(iOS)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { commitFeed() }
#endif
            Button("Add") { commitFeed() }
                .buttonStyle(.bordered)
                .disabled(!isValidURL(newFeedURL))
        }
    }

    private func commitFeed() {
        guard isValidURL(newFeedURL) else { return }
        vm.addFeed(urlString: newFeedURL)
        newFeedURL = ""
    }

    private func isValidURL(_ string: String) -> Bool {
        guard !string.isEmpty, let url = URL(string: string), url.scheme != nil else { return false }
        return true
    }

    private func hostName(for urlString: String) -> String {
        guard let host = URL(string: urlString)?.host else { return urlString }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - OPML (macOS only)

#if os(macOS)
    private var opmlSection: some View {
        Section {
            Button {
                showingOPMLImporter = true
            } label: {
                Label("Import OPML File…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
        } footer: {
            Text("Import multiple feeds at once from an OPML file exported by another RSS reader.")
        }
    }

    private func importOPML(_ result: Result<URL, Error>) {
        guard case .success(let url) = result,
              let data = try? Data(contentsOf: url) else { return }
        vm.importOPML(data: data)
    }
#endif
}
