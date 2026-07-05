import SwiftUI

/// A single "Suggested Feeds" row — name/URL with a trailing add/remove
/// toggle. Shared by SettingsView and PreferencesWizardView so the two
/// suggested-feeds lists can't drift.
struct SuggestedFeedRow: View {
    let feed: SuggestedRSSFeed
    let isAdded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name).font(.body)
                Text(feed.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(action: onToggle) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isAdded ? Color.accentColor : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdded ? "Remove \(feed.name)" : "Add \(feed.name)")
        }
        .padding(.vertical, 4)
    }
}
