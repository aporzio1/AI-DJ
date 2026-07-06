import SwiftUI

/// Kokoro-specific rows shown by `VoiceSection` inside its "Voice" Section
/// when `.kokoro` is the selected TTS provider. Not a Form Section of its
/// own — this is a row group, embedded in the parent's Section content.
struct KokoroSection: View {
    @Bindable var vm: SettingsViewModel
    let voicePreview: VoicePreviewPlayer
    @State private var showingRemoveConfirm = false

    var body: some View {
        Group {
            Picker("Voice", selection: $vm.kokoroVoice) {
                ForEach(KokoroVoice.available) { voice in
                    Text(voice.displayName).tag(voice.rawValue)
                }
            }
            .onChange(of: vm.kokoroVoice) { _, _ in
                vm.save()
                voicePreview.stopPreview()
            }

            Button {
                Task { await voicePreview.togglePreview(voiceIdentifier: vm.kokoroVoice) }
            } label: {
                switch voicePreview.previewState {
                case .idle:
                    Label("Preview Voice", systemImage: "play.circle")
                case .rendering:
                    HStack(spacing: 8) {
                        ProgressView()
#if os(macOS)
                            .controlSize(.small)
#endif
                        Text("Rendering…")
                    }
                case .playing:
                    Label("Stop Preview", systemImage: "stop.circle")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!voicePreview.modelInstalled || voicePreview.downloading || voicePreview.removing || voicePreview.previewState == .rendering)

            LabeledContent("Model") {
                HStack(spacing: 8) {
                    Image(systemName: voicePreview.modelInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(voicePreview.modelInstalled ? Color.green : Color.secondary)
                    Text(voicePreview.modelInstalled ? "Installed" : "Not Installed")
                        .foregroundStyle(.secondary)
                }
            }

            if voicePreview.downloading {
                HStack(spacing: 12) {
                    ProgressView()
#if os(macOS)
                        .controlSize(.small)
#endif
                    Text("Downloading model…").foregroundStyle(.secondary)
                }
                .frame(minHeight: 44, alignment: .leading)
            } else {
                Button {
                    Task { await voicePreview.downloadModel() }
                } label: {
                    Label(
                        voicePreview.modelInstalled ? "Re-download Model" : "Download Model",
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(voicePreview.removing)
            }

            Button(role: .destructive) {
                showingRemoveConfirm = true
            } label: {
                Label("Remove Model", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(!voicePreview.modelInstalled || voicePreview.downloading || voicePreview.removing)

            if let err = voicePreview.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(
            "Remove Kokoro model?",
            isPresented: $showingRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove Model", role: .destructive) {
                Task { await voicePreview.removeModel() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes ~300 MB of cached CoreML model files. The next DJ segment using Kokoro will re-download them.")
        }
    }
}
