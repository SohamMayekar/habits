import SwiftUI

struct HabitDraft: Equatable, Sendable {
    var name: String = ""
    var note: String = ""
    var colorName: String = Habit.colorOptions.first?.key ?? "green"
    var systemIcon: String = Habit.iconOptions.first ?? "circle"

    init(
        name: String = "",
        note: String = "",
        colorName: String = Habit.colorOptions.first?.key ?? "green",
        systemIcon: String = Habit.iconOptions.first ?? "circle"
    ) {
        self.name = String(name.prefix(Habit.maxNameLength))
        self.note = String(note.prefix(Habit.maxNoteLength))
        self.colorName = colorName
        self.systemIcon = systemIcon
    }

    init(habit: Habit) {
        self.init(
            name: habit.name,
            note: habit.note,
            colorName: habit.colorName,
            systemIcon: habit.systemIcon
        )
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct HabitEditorView: View {
    enum Mode {
        case create
        case edit

        var navigationTitle: LocalizedStringKey {
            switch self {
            case .create: "New Habit"
            case .edit:   "Edit Habit"
            }
        }

        var actionTitle: LocalizedStringKey {
            switch self {
            case .create: "Begin"
            case .edit:   "Save"
            }
        }
    }

    let mode: Mode
    @Binding var draft: HabitDraft
    let validationMessage: String?
    let isSavingDisabled: Bool
    let save:   () -> Void
    let cancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var nameFieldFocused: Bool

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 4 : 6
        return Array(repeating: GridItem(.flexible(), spacing: AppSpacing.item), count: count)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Name + note always visible at medium detent height
                Section {
                    TextField("What do you want to practice?", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFieldFocused)
                        .onChange(of: draft.name) { _, newValue in
                            if newValue.count > Habit.maxNameLength {
                                draft.name = String(newValue.prefix(Habit.maxNameLength))
                            }
                        }
                        .accessibilityHint("Keep it short and easy to recognize later.")

                    TextField("Optional note", text: $draft.note)
                        .onChange(of: draft.note) { _, newValue in
                            if newValue.count > Habit.maxNoteLength {
                                draft.note = String(newValue.prefix(Habit.maxNoteLength))
                            }
                        }
                        .accessibilityHint("A short cue — where or when this habit fits.")
                } footer: {
                    Text(mode == .create
                         ? "Small enough that you'd do it even on a hard day."
                         : "Keep it clear enough to return to without thinking.")
                }

                // Color and icon — pull the sheet to .large to reveal
                Section("Color") {
                    LazyVGrid(columns: columns, spacing: AppSpacing.item) {
                        ForEach(Habit.colorOptions, id: \.key) { option in
                            Button {
                                draft.colorName = option.key
                                selectionHaptic()
                            } label: {
                                Circle()
                                    .fill(Habit.color(for: option.key))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if draft.colorName == option.key {
                                            Circle()
                                                .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 3)
                                                .padding(2)
                                        }
                                    }
                                    .scaleEffect(draft.colorName == option.key ? 1.1 : 1)
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Circle())
                            .accessibilityLabel("\(option.displayName) color")
                            .accessibilityHint(draft.colorName == option.key ? "Selected." : "Double tap to select.")
                            .accessibilityAddTraits(draft.colorName == option.key ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, AppSpacing.compact)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: draft.colorName)
                }

                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: AppSpacing.item) {
                        ForEach(Habit.iconOptions, id: \.self) { icon in
                            Button {
                                draft.systemIcon = icon
                                selectionHaptic()
                            } label: {
                                Image(systemName: icon)
                                    .font(AppType.icon)
                                    .foregroundStyle(draft.systemIcon == icon ? .white : .primary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle()
                                            .fill(draft.systemIcon == icon
                                                  ? Habit.color(for: draft.colorName)
                                                  : Color(uiColor: .tertiarySystemFill))
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Circle())
                            .accessibilityLabel("\(icon) icon")
                            .accessibilityHint(draft.systemIcon == icon ? "Selected." : "Double tap to select.")
                            .accessibilityAddTraits(draft.systemIcon == icon ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, AppSpacing.compact)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: draft.systemIcon)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: draft.colorName)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            // systemGroupedBackground: legible gray in light mode,
            // dark charcoal in dark mode — the correct adaptive base for forms.
            .background(Color(uiColor: .systemGroupedBackground))
            .appScrollChrome()
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .accessibilityHint("Dismisses without saving.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionTitle, action: save)
                        .font(AppType.bodyEmphasis)
                        .disabled(isSavingDisabled)
                        .accessibilityHint(mode == .create ? "Creates the habit." : "Saves your changes.")
                }
            }
            .task {
                // Wait for the sheet to fully render before focusing,
                // but keep it short since we open at .large (no detent resize).
                try? await Task.sleep(for: .milliseconds(150))
                nameFieldFocused = true
            }
        }
        // Full height — keyboard appears without causing a detent‐resize stutter.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func selectionHaptic() {
        HapticManager.shared.play(.optionChanged)
    }
}
