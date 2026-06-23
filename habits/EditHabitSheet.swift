import SwiftUI

struct EditHabitSheet: View {
    @Binding var isPresented: Bool
    let habit: Habit

    @Environment(HabitStore.self) private var store
    @State private var draft: HabitDraft
    @State private var validationMessage: String?

    init(isPresented: Binding<Bool>, habit: Habit) {
        _isPresented = isPresented
        self.habit = habit
        _draft = State(initialValue: HabitDraft(habit: habit))
    }

    var body: some View {
        HabitEditorView(
            mode: .edit,
            draft: $draft,
            validationMessage: validationMessage ?? store.validationMessage(for: draft, excluding: habit.id),
            isSavingDisabled: draft.trimmedName.isEmpty,
            save: saveAndDismiss,
            cancel: { isPresented = false }
        )
    }

    private func saveAndDismiss() {
        switch store.update(habit, draft: draft) {
        case .success:
            HapticManager.shared.play(.habitSaved)
            isPresented = false
        case .failure(let error):
            validationMessage = error.errorDescription
            HapticManager.shared.play(.validationWarning)
        }
    }
}
