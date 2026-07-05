import SwiftUI

struct SettingsView: View {
    @Bindable var vm: SettingsViewModel
    @State private var availableVoices: [VoiceOption] = []
    @State private var showingPersonaList = false

    private let djVoice: DJVoiceRouter
    @State private var voicePreview: VoicePreviewPlayer

    init(vm: SettingsViewModel, djVoice: DJVoiceRouter) {
        self.vm = vm
        self.djVoice = djVoice
        self._voicePreview = State(initialValue: VoicePreviewPlayer(djVoice: djVoice))
    }

    var body: some View {
        Form {
            musicServicesSection
            djSection
            VoiceSection(vm: vm, voicePreview: voicePreview, availableVoices: availableVoices)
            NewsSection(vm: vm)
            ICloudSection(vm: vm)
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            availableVoices = VoiceOption.installedEnglish()
            // If the previously-saved voice isn't installed anymore, fall back to default
            // so the Picker doesn't show an "invalid selection" warning.
            if !vm.voiceIdentifier.isEmpty,
               !availableVoices.contains(where: { $0.id == vm.voiceIdentifier }) {
                vm.voiceIdentifier = ""
                vm.save()
            }
            voicePreview.refreshModelStatus()
        }
    }

    // MARK: - Music Services

    private var musicServicesSection: some View {
        Section {
            LabeledContent("Apple Music") {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Authorized")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Music Services")
        } footer: {
            Text("Apple Music authorization is managed in the system Settings app.")
        }
    }

    // MARK: - DJ

    private var djSection: some View {
        Section {
            Toggle("Enable DJ", isOn: $vm.djEnabled)
                .onChange(of: vm.djEnabled) { _, _ in vm.save() }

            Picker("Frequency", selection: $vm.djFrequency) {
                ForEach(DJFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!vm.djEnabled)
            .onChange(of: vm.djFrequency) { _, _ in vm.save() }

            HStack {
                Text("Your Name")
                Spacer(minLength: 16)
                TextField("", text: $vm.listenerName)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 240)
                    .onChange(of: vm.listenerName) { _, _ in vm.save() }
            }

            Button {
                showingPersonaList = true
            } label: {
                HStack {
                    Text("Persona")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(vm.persona.name)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("DJ")
        } footer: {
            Text("The DJ introduces tracks and adds commentary between songs. Your name may be used occasionally to personalize greetings.")
        }
        .sheet(isPresented: $showingPersonaList) {
            PersonaListView(vm: vm)
        }
    }
}
