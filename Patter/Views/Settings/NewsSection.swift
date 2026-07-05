import SwiftUI

/// News toggle/frequency plus, when DJ + news are both enabled, the RSS feed
/// list, suggested feeds, and (macOS) OPML import. The news toggle itself
/// stays visible-but-disabled when the DJ is off, so it's always rendered —
/// only the feed-management Sections below it are conditionally hidden.
struct NewsSection: View {
    @Bindable var vm: SettingsViewModel
    @State private var newFeedURL = ""
    @State private var showingOPMLImporter = false
    @State private var feedPendingRemoval: String?

    var body: some View {
        Group {
            newsSection
            if vm.djEnabled && vm.newsEnabled {
                feedsSection
                suggestedFeedsSection
#if os(macOS)
                opmlSection
#endif
            }
        }
#if os(macOS)
        .fileImporter(isPresented: $showingOPMLImporter,
                      allowedContentTypes: [.xml, .data],
                      onCompletion: importOPML)
#endif
    }

    // MARK: - News

    private var newsSection: some View {
        Section {
            Toggle("Include News Headlines", isOn: $vm.newsEnabled)
                .disabled(!vm.djEnabled)
                .onChange(of: vm.newsEnabled) { _, _ in vm.save() }

            Picker("Frequency", selection: $vm.newsFrequency) {
                ForEach(NewsFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!vm.djEnabled || !vm.newsEnabled)
            .onChange(of: vm.newsFrequency) { _, _ in vm.save() }
        } header: {
            Text("News")
        } footer: {
            Text("When enabled, the DJ will reference a recent headline from your RSS feeds. Frequency controls how often a headline is injected into a DJ segment.")
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
        .confirmationDialog(
            "Remove this feed?",
            isPresented: Binding(
                get: { feedPendingRemoval != nil },
                set: { if !$0 { feedPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let urlString = feedPendingRemoval {
                    deleteFeed(urlString: urlString)
                }
                feedPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                feedPendingRemoval = nil
            }
        } message: {
            Text(feedPendingRemoval.map(hostName(for:)) ?? "")
        }
    }

    private var suggestedFeedsSection: some View {
        Section {
            ForEach(SuggestedRSSFeeds.all) { feed in
                suggestedFeedRow(feed)
            }
        } header: {
            Text("Suggested Feeds")
        } footer: {
            Text("Tap to add a curated feed. Tap again to remove.")
        }
    }

    private func suggestedFeedRow(_ feed: SuggestedRSSFeed) -> some View {
        let isAdded = vm.feedURLStrings.contains(feed.url)
        return SuggestedFeedRow(feed: feed, isAdded: isAdded) {
            if isAdded {
                vm.feedURLStrings.removeAll { $0 == feed.url }
                vm.save()
            } else {
                vm.addFeed(urlString: feed.url)
            }
        }
    }

    private func feedRow(_ urlString: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hostName(for: urlString))
                    .font(.body)
                Text(urlString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                feedPendingRemoval = urlString
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove feed")
        }
        .padding(.vertical, 4)
    }

    private func deleteFeed(urlString: String) {
        if let idx = vm.feedURLStrings.firstIndex(of: urlString) {
            vm.removeFeed(at: IndexSet(integer: idx))
        }
    }

    private var addFeedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Feed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField(
                    "",
                    text: $newFeedURL,
                    prompt: Text(verbatim: "https://example.com/feed.xml")
                )
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { commitFeed() }
#endif
                Button("Add") { commitFeed() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!OPMLParser.isValidFeedURL(newFeedURL))
            }
        }
        .padding(.vertical, 4)
    }

    private func commitFeed() {
        guard OPMLParser.isValidFeedURL(newFeedURL) else { return }
        vm.addFeed(urlString: newFeedURL)
        newFeedURL = ""
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
