import SwiftUI

/// Sheet for creating a new custom persona or editing an existing one.
/// Built-ins never reach this view — callers duplicate first via
/// `SettingsViewModel.duplicatePersona(_:)` and edit the copy.
struct PersonaEditorView: View {
    @Bindable var vm: SettingsViewModel

    /// The persona being edited. `nil` means "create new."
    let editing: DJPersona?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var styleDescriptor: String = ""

    private var characterCount: Int { styleDescriptor.count }
    private var isOverLimit: Bool { characterCount > SettingsViewModel.maxStyleDescriptorLength }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isOverLimit
    }

    private var navTitle: String {
        editing == nil ? "New Persona" : "Edit Persona"
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
            .navigationTitle(navTitle)
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
                if let editing {
                    name = editing.name
                    styleDescriptor = editing.styleDescriptor
                }
            }
#if os(macOS)
            .frame(minWidth: 520, minHeight: 480)
#endif
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !isOverLimit else { return }
        if let editing {
            vm.updateCustomPersona(id: editing.id, name: trimmedName, styleDescriptor: styleDescriptor)
        } else {
            vm.addCustomPersona(name: trimmedName, styleDescriptor: styleDescriptor)
        }
        dismiss()
    }
}
