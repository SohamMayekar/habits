import SwiftUI

struct AddHabitSheet: View {
    @Binding var isPresented: Bool

    @Environment(HabitStore.self) private var store

    @State private var draft = HabitDraft()
    @State private var validationMessage: String?

    var body: some View {
        HabitEditorView(
            mode: .create,
            draft: $draft,
            validationMessage: validationMessage ?? store.validationMessage(for: draft),
            isSavingDisabled: draft.trimmedName.isEmpty,
            save: saveAndDismiss,
            cancel: { isPresented = false }
        )
    }

    private func saveAndDismiss() {
        switch store.add(draft: draft) {
        case .success:
            HapticManager.shared.play(.habitSaved)
            isPresented = false
        case .failure(let error):
            validationMessage = error.errorDescription
            HapticManager.shared.play(.validationWarning)
        }
    }
}
