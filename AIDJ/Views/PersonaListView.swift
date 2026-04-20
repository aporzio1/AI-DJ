import SwiftUI

/// Full persona picker: built-ins on top, user customs below. Tap a row to
/// activate; each row has a trailing menu with Edit / Duplicate / Delete
/// (filtered by whether the persona is a built-in or a custom).
struct PersonaListView: View {
    @Bindable var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editorTarget: EditorTarget?
    @State private var pendingDeletion: DJPersona?

    /// Identifiable wrapper that drives `.sheet(item:)` for the editor. Using
    /// an item-driven sheet avoids the classic "state read at sheet-creation
    /// time" bug.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let persona: DJPersona?   // nil = create new
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(DJPersona.builtIns) { persona in
                        personaRow(persona)
                    }
                }

                if !vm.customPersonas.isEmpty {
                    Section("Your Personas") {
                        ForEach(vm.customPersonas) { persona in
                            personaRow(persona)
                        }
                    }
                }
            }
            .navigationTitle("Personas")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = EditorTarget(persona: nil)
                    } label: {
                        Label("New Persona", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                PersonaEditorView(vm: vm, editing: target.persona)
            }
            .confirmationDialog(
                "Delete \(pendingDeletion?.name ?? "persona")?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { persona in
                Button("Delete", role: .destructive) {
                    vm.deleteCustomPersona(id: persona.id)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { _ in
                Text("This persona will be removed. If it's the active persona, the DJ falls back to the built-in default.")
            }
#if os(macOS)
            .frame(minWidth: 520, minHeight: 480)
#endif
        }
    }

    // MARK: - Row

    private func personaRow(_ persona: DJPersona) -> some View {
        let isActive = vm.activePersonaID == persona.id
        return HStack(spacing: 12) {
            Button {
                vm.setActivePersona(id: persona.id)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(persona.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if persona.isBuiltIn {
                                Text("Built-in")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(persona.styleDescriptor)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    editOrDuplicate(persona)
                } label: {
                    Label(persona.isBuiltIn ? "Duplicate & Edit" : "Edit", systemImage: "pencil")
                }
                Button {
                    let copy = vm.duplicatePersona(persona, activate: false)
                    _ = copy
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                if !persona.isBuiltIn {
                    Divider()
                    Button(role: .destructive) {
                        pendingDeletion = persona
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More actions for \(persona.name)")
        }
        .padding(.vertical, 4)
    }

    /// For built-ins, duplicate first and open the editor on the copy.
    /// For customs, open the editor on the persona itself.
    private func editOrDuplicate(_ persona: DJPersona) {
        if persona.isBuiltIn {
            let copy = vm.duplicatePersona(persona, activate: true)
            editorTarget = EditorTarget(persona: copy)
        } else {
            editorTarget = EditorTarget(persona: persona)
        }
    }
}
