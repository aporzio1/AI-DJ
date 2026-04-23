import SwiftUI
import AVFoundation

/// Four-step first-launch preferences wizard. Runs after the Apple
/// Intelligence + MusicKit gates but before the main app loads, so the
/// user lands in a configured state instead of staring at an empty
/// Library tab with no DJ name set.
///
/// Only Step 1 (name) is required; every other step offers a sensible
/// default and a "Continue" that moves forward.
struct PreferencesWizardView: View {
    @Bindable var settings: SettingsViewModel
    let onComplete: () -> Void

    @State private var step = 0
    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(step + 1), total: Double(totalSteps))
                .padding(.horizontal, 24)
                .padding(.top, 24)

            ScrollView {
                VStack(spacing: 16) {
                    Group {
                        switch step {
                        case 0: nameStep
                        case 1: djStep
                        case 2: newsStep
                        case 3: iCloudStep
                        default: EmptyView()
                        }
                    }
                    .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }

            navButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
#endif
    }

    // MARK: - Step 1: Name

    private var nameStep: some View {
        VStack(spacing: 16) {
            stepHeader(
                icon: "person.crop.circle",
                title: "What should the DJ call you?",
                subtitle: "Used occasionally in between-track banter. We pre-filled your Mac account name — change it if you want."
            )
            TextField("Your name", text: $settings.listenerName)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
#if os(iOS)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
#endif
        }
    }

    // MARK: - Step 2: DJ (frequency + voice)

    private var djStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                icon: "waveform.circle",
                title: "Set up your DJ",
                subtitle: "Decide how often the DJ talks and which voice it uses between tracks."
            )

            Toggle("Enable DJ", isOn: $settings.djEnabled)
                .font(.title3)
                .padding(.vertical, 4)

            Text("Talk Frequency")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
            Picker("Frequency", selection: $settings.djFrequency) {
                ForEach(DJFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.djEnabled)
            .labelsHidden()

            Divider().padding(.vertical, 8)

            Text("Voice Provider")
                .font(.subheadline.weight(.semibold))
            Picker("Provider", selection: $settings.ttsProvider) {
                ForEach(TTSProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.djEnabled)
            .labelsHidden()

            Text("Voice")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
            voicePicker
                .disabled(!settings.djEnabled)

            if settings.ttsProvider == .openAI {
                Text("You'll need to paste an OpenAI API key in Settings for this to work. We'll fall back to Device Voices until you do.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else if settings.ttsProvider == .kokoro {
                Text("Kokoro downloads its model on the first DJ segment (~300 MB). Subsequent segments are instant.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Text("All of this is editable in Settings later.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var voicePicker: some View {
        switch settings.ttsProvider {
        case .system:
            Picker("Voice", selection: $settings.voiceIdentifier) {
                Text("System Default").tag("")
                ForEach(installedEnglishVoices, id: \.identifier) { voice in
                    Text("\(voice.name) — \(qualityLabel(for: voice))").tag(voice.identifier)
                }
            }
            .labelsHidden()
        case .openAI:
            Picker("Voice", selection: $settings.openAIVoice) {
                ForEach(OpenAITTSVoice.allCases) { voice in
                    Text(voice.displayName).tag(voice.rawValue)
                }
            }
            .labelsHidden()
        case .kokoro:
            Picker("Voice", selection: $settings.kokoroVoice) {
                ForEach(KokoroVoice.allCases) { voice in
                    Text(voice.displayName).tag(voice.rawValue)
                }
            }
            .labelsHidden()
        }
    }

    /// Load installed English AVSpeechSynthesis voices once per wizard render
    /// — the list doesn't change between taps.
    private var installedEnglishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }

    private func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium:  return "Premium"
        case .enhanced: return "Enhanced"
        default:        return "Compact"
        }
    }

    // MARK: - Step 3: News

    private var newsStep: some View {
        VStack(spacing: 16) {
            stepHeader(
                icon: "newspaper",
                title: "Mix in some news?",
                subtitle: "If you turn this on, the DJ will reference a recent headline from your RSS feeds. You can skip this and add feeds later."
            )
            Toggle("Include News Headlines", isOn: $settings.newsEnabled)
                .font(.title3)
                .padding(.vertical, 4)

            Picker("Frequency", selection: $settings.newsFrequency) {
                ForEach(NewsFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.newsEnabled)

            if settings.newsEnabled {
                suggestedFeedsSection
            }
        }
    }

    @ViewBuilder
    private var suggestedFeedsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested feeds")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 12)
            ForEach(Self.suggestedFeeds) { feed in
                suggestedFeedRow(feed)
            }
            Text("Add or remove feeds any time in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestedFeedRow(_ feed: SuggestedFeed) -> some View {
        let isAdded = settings.feedURLStrings.contains(feed.url)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name).font(.body)
                Text(feed.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button {
                if isAdded {
                    settings.feedURLStrings.removeAll { $0 == feed.url }
                    settings.save()
                } else {
                    settings.addFeed(urlString: feed.url)
                }
            } label: {
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

    // MARK: - Step 4: iCloud

    private var iCloudStep: some View {
        VStack(spacing: 16) {
            stepHeader(
                icon: "icloud",
                title: "Sync across devices?",
                subtitle: "Keep your preferences, feeds, and personas in sync on every device signed in to the same iCloud account. Your OpenAI API key stays on this device."
            )
            Toggle("Sync with iCloud", isOn: Binding(
                get: { settings.iCloudSyncEnabled },
                set: { settings.setiCloudSyncEnabled($0) }
            ))
            .font(.title3)
            .padding(.vertical, 4)

            Text("You can flip this any time in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }

    // MARK: - Header + nav

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 4)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var navButtons: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
            Spacer()
            Button(isLastStep ? "Start Listening" : "Continue") {
                if isLastStep {
                    settings.save()
                    onComplete()
                } else {
                    step += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .disabled(!canContinue)
        }
    }

    private var isLastStep: Bool { step == totalSteps - 1 }

    private var canContinue: Bool {
        switch step {
        case 0:
            return !settings.listenerName.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    // MARK: - Suggested feeds data

    private struct SuggestedFeed: Identifiable {
        let id = UUID()
        let name: String
        let url: String
    }

    private static let suggestedFeeds: [SuggestedFeed] = [
        .init(name: "NPR Top Stories", url: "https://feeds.npr.org/1001/rss.xml"),
        .init(name: "Hacker News", url: "https://hnrss.org/newest"),
        .init(name: "BBC Top Stories", url: "https://feeds.bbci.co.uk/news/rss.xml"),
        .init(name: "BBC World News", url: "https://feeds.bbci.co.uk/news/world/rss.xml"),
        .init(name: "BBC Technology", url: "https://feeds.bbci.co.uk/news/technology/rss.xml"),
        .init(name: "BBC Business", url: "https://feeds.bbci.co.uk/news/business/rss.xml"),
        .init(name: "CBS Top Stories", url: "https://www.cbsnews.com/latest/rss/main"),
        .init(name: "CBS World", url: "https://www.cbsnews.com/latest/rss/world"),
        .init(name: "CBS Technology", url: "https://www.cbsnews.com/latest/rss/technology"),
        .init(name: "The Guardian", url: "https://www.theguardian.com/rss"),
        .init(name: "Guardian World", url: "https://www.theguardian.com/world/rss"),
        .init(name: "Guardian Technology", url: "https://www.theguardian.com/technology/rss"),
        .init(name: "WIRED Top Stories", url: "https://www.wired.com/feed/rss"),
        .init(name: "WIRED AI", url: "https://www.wired.com/feed/tag/ai/latest/rss"),
        .init(name: "WIRED Security", url: "https://www.wired.com/feed/category/security/latest/rss"),
        .init(name: "TechCrunch", url: "https://techcrunch.com/feed/"),
        .init(name: "BleepingComputer", url: "https://www.bleepingcomputer.com/feed/"),
        .init(name: "Le Monde World", url: "https://www.lemonde.fr/en/international/rss_full.xml")
    ]
}
