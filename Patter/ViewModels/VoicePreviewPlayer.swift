import AVFoundation

/// Owns Kokoro's on-device model lifecycle (install/download/remove state)
/// and the short-sample preview playback state machine. Extracted from
/// SettingsView because the two are tightly coupled — removing the model
/// must also stop any in-flight preview, and both surface errors through the
/// same `errorMessage`.
@MainActor
@Observable
final class VoicePreviewPlayer {

    enum PreviewState: Equatable {
        case idle, rendering, playing
    }

    private(set) var modelInstalled: Bool
    private(set) var downloading = false
    private(set) var removing = false
    private(set) var errorMessage: String?
    private(set) var previewState: PreviewState = .idle

    private let djVoice: DJVoiceRouter
    private var player: AVAudioPlayer?

    private static let previewScript = "Hey, this is your DJ checking in. Coming up next, another great track."

    init(djVoice: DJVoiceRouter) {
        self.djVoice = djVoice
        self.modelInstalled = djVoice.isKokoroModelInstalled
    }

    func refreshModelStatus() {
        modelInstalled = djVoice.isKokoroModelInstalled
    }

    func downloadModel() async {
        downloading = true
        errorMessage = nil
        do {
            try await djVoice.prepareKokoroModel()
            modelInstalled = djVoice.isKokoroModelInstalled
        } catch {
            errorMessage = error.localizedDescription
        }
        downloading = false
    }

    func removeModel() async {
        removing = true
        errorMessage = nil
        stopPreview()
        do {
            try await djVoice.removeKokoroModel()
            modelInstalled = djVoice.isKokoroModelInstalled
        } catch {
            errorMessage = error.localizedDescription
        }
        removing = false
    }

    func togglePreview(voiceIdentifier: String) async {
        switch previewState {
        case .idle:      await startPreview(voiceIdentifier: voiceIdentifier)
        case .rendering: return
        case .playing:   stopPreview()
        }
    }

    func stopPreview() {
        player?.stop()
        player = nil
        if previewState == .playing {
            previewState = .idle
        }
    }

    private func startPreview(voiceIdentifier: String) async {
        previewState = .rendering
        errorMessage = nil
        do {
            let url = try await djVoice.renderKokoroSample(script: Self.previewScript, voiceIdentifier: voiceIdentifier)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            player = newPlayer
            previewState = .playing
            newPlayer.play()
            let duration = newPlayer.duration
            try? await Task.sleep(for: .seconds(duration + 0.15))
            // Only reset state if this preview is still the active one.
            if player === newPlayer {
                player = nil
                previewState = .idle
            }
        } catch {
            errorMessage = error.localizedDescription
            player = nil
            previewState = .idle
        }
    }
}
