import SwiftUI

/// Sheet for editing the DJ persona's name and LLM instructions.
/// Phase 1 — edits the single active persona in place. Phase 2 will add
/// a persona list, built-in presets, and add/delete.
struct PersonaEditorView: View {
    @Bindable var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var styleDescriptor: String = ""

    private var characterCount: Int { styleDescriptor.count }
    private var isOverLimit: Bool { characterCount > SettingsViewModel.maxStyleDescriptorLength }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isOverLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shown in Settings. Not spoken aloud unless the instructions ask the DJ to use it.")
                }

                Section {
                    TextEditor(text: $styleDescriptor)
                        .frame(minHeight: 180)
                        .font(.body)
                } header: {
                    HStack {
                        Text("Instructions")
                        Spacer()
                        Text("\(characterCount)/\(SettingsViewModel.maxStyleDescriptorLength)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(isOverLimit ? Color.red : Color.secondary)
                    }
                } footer: {
                    Text("Prompt injected into every DJ segment. Describe tone, personality, and any do's/don'ts. Keep it under \(SettingsViewModel.maxStyleDescriptorLength) characters — longer instructions tend to drift the DJ off-topic.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Persona")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear {
                name = vm.persona.name
                styleDescriptor = vm.persona.styleDescriptor
            }
#if os(macOS)
            .frame(minWidth: 520, minHeight: 480)
#endif
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !isOverLimit else { return }
        vm.updatePersona(name: trimmedName, styleDescriptor: styleDescriptor)
        dismiss()
    }
}
