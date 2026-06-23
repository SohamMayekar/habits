import SwiftUI

struct HabitRowView: View {

    let habit: Habit
    let isCompletedToday: Bool
    let onPrimaryAction: () -> Void
    let onPauseToggle: () -> Void
    var onEdit:   (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var completionPulse = 0
    @State private var rippleScale: CGFloat = 0.85
    @State private var rippleOpacity: CGFloat = 0
    @State private var showRipple = false
    @State private var cardWidth: CGFloat = 0

    private var rowSpring: Animation? {
        reduceMotion ? nil : .spring(duration: 0.52, bounce: 0.18, blendDuration: 0)
    }

    var body: some View {
        let isPaused   = habit.isPaused
        let isCompleted = isCompletedToday

        Button {
            handlePrimaryAction()
        } label: {
            HStack(alignment: .top, spacing: 16) {
                iconView(isCompleted: isCompleted, isPaused: isPaused)

                VStack(alignment: .leading, spacing: 5) {
                    Text(habit.name)
                        .font(AppType.bodyEmphasis)
                        .foregroundStyle(isPaused || isCompleted ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)

                    let meta = metadataLine(isCompleted: isCompleted, isPaused: isPaused)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(AppType.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if dynamicTypeSize.isAccessibilitySize {
                    completionControl(isCompleted: isCompleted, isPaused: isPaused)
                        .padding(.top, 2)
                } else {
                    Spacer(minLength: 8)
                    completionControl(isCompleted: isCompleted, isPaused: isPaused)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(HabitRowBackground(habit: habit, isCompleted: isCompleted, isPaused: isPaused))
            // Capture actual rendered width for the context-menu preview frame.
            .background {
                GeometryReader { geo in
                    Color.clear.onAppear { cardWidth = geo.size.width }
                }
            }
            .scaleEffect(isCompleted ? 0.985 : 1)
            .opacity(isPaused ? 0.68 : (isCompleted ? 0.82 : 1))
        }
        .buttonStyle(ScaleButtonStyle())
        .contextMenu {
            if let onEdit {
                Button {
                    HapticManager.shared.play(.openComposer)
                    onEdit()
                } label: {
                    Label("Edit Habit", systemImage: "pencil")
                }
            }

            Button {
                onPauseToggle()
                HapticManager.shared.play(.pauseStateChanged)
            } label: {
                Label(
                    habit.isPaused ? "Resume Habit" : "Pause Habit",
                    systemImage: habit.isPaused ? "play.circle" : "pause.circle"
                )
            }

            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Habit", systemImage: "trash")
                }
            }
        } preview: {
            // Exact card width pinned — without this, the preview window
            // has no parent constraint and collapses to minimum intrinsic width.
            cardPreview(isCompleted: isCompleted, isPaused: isPaused)
                .frame(width: cardWidth > 0 ? cardWidth : nil)
        }
        .animation(rowSpring, value: isCompleted)
        .animation(rowSpring, value: isPaused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(isCompleted: isCompleted, isPaused: isPaused))
        .accessibilityHint(accessibilityHint(isCompleted: isCompleted, isPaused: isPaused))
        .accessibilityAction(named: Text(primaryAccessibilityActionTitle(isCompleted: isCompleted, isPaused: isPaused))) {
            handlePrimaryAction()
        }
        .accessibilityAction(named: Text(habit.isPaused ? "Resume habit" : "Pause habit")) {
            onPauseToggle()
            HapticManager.shared.play(.pauseStateChanged)
        }
        .accessibilityAction(named: Text("Edit habit"))   { onEdit?() }
        .accessibilityAction(named: Text("Delete habit")) { onDelete?() }
    }

    @ViewBuilder
    private func cardPreview(isCompleted: Bool, isPaused: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            iconView(isCompleted: isCompleted, isPaused: isPaused)

            VStack(alignment: .leading, spacing: 5) {
                Text(habit.name)
                    .font(AppType.bodyEmphasis)
                    .foregroundStyle(isPaused || isCompleted ? .secondary : .primary)

                if !habit.note.isEmpty {
                    Text(habit.note)
                        .font(AppType.footnote)
                        .foregroundStyle(.secondary)
                } else if isCompleted {
                    Text("Done today")
                        .font(AppType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)
            completionControl(isCompleted: isCompleted, isPaused: isPaused)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            HabitRowBackground(habit: habit, isCompleted: isCompleted, isPaused: isPaused)
        )
        .scaleEffect(isCompleted ? 0.985 : 1)
        .opacity(isPaused ? 0.68 : (isCompleted ? 0.82 : 1))
    }

    // MARK: - Subviews

    private func iconView(isCompleted: Bool, isPaused: Bool) -> some View {
        ZStack {
            Circle()
                .fill(habit.tintColor.opacity(isPaused ? 0.12 : (isCompleted ? 0.16 : 0.22)))
                .frame(width: 46, height: 46)

            Image(systemName: isPaused ? "pause.fill" : habit.systemIcon)
                .font(AppType.icon)
                .foregroundStyle(isPaused || isCompleted ? .secondary : habit.tintColor)
        }
    }

    // MARK: - Completion Control

    private func completionControl(isCompleted: Bool, isPaused: Bool) -> some View {
        ZStack {
            if showRipple && !reduceMotion {
                Circle()
                    .strokeBorder(
                        habit.tintColor.opacity(rippleOpacity * 0.55),
                        lineWidth: 2
                    )
                    .frame(width: 34, height: 34)
                    .scaleEffect(rippleScale)
                    .allowsHitTesting(false)
            }

            Circle()
                .fill(isPaused ? Color.todayMutedFill : (isCompleted ? habit.tintColor : Color.todayControlFill))
                .frame(width: 34, height: 34)

            Circle()
                .stroke(isCompleted || isPaused ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
                .frame(width: 34, height: 34)

            Image(systemName: isPaused ? "play.fill" : (isCompleted ? "checkmark" : "circle"))
                .font(isCompleted || isPaused ? AppType.captionStrong : AppType.iconSmall)
                .foregroundStyle(controlForegroundColor(isCompleted: isCompleted, isPaused: isPaused))
                .symbolEffect(.bounce.down.byLayer, value: completionPulse)
                .scaleEffect(isCompleted ? 1 : 0.7)
                .animation(
                    reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.45),
                    value: isCompleted
                )
        }
        .frame(width: 44, height: 44)
    }

    // MARK: - Metadata Copy

    private func metadataLine(isCompleted: Bool, isPaused: Bool) -> String {
        if isPaused { return "Paused" }
        if !habit.note.isEmpty { return habit.note }
        if isCompleted { return "Done today" }
        return ""
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        if habit.isPaused {
            onPrimaryAction()
            HapticManager.shared.play(.pauseStateChanged)
            completionPulse += 1
            return
        }

        let wasCompleted = isCompletedToday
        onPrimaryAction()
        HapticManager.shared.play(wasCompleted ? .habitUnchecked : .habitCompleted)
        completionPulse += 1

        if !wasCompleted && !reduceMotion {
            triggerRipple()
        }
    }

    // MARK: - Ripple

    private func triggerRipple() {
        rippleScale = 0.85
        rippleOpacity = 1
        showRipple = true

        withAnimation(.easeOut(duration: 0.5)) {
            rippleScale = 2.6
            rippleOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            showRipple = false
            rippleScale = 0.85
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(isCompleted: Bool, isPaused: Bool) -> String {
        isPaused
            ? "\(habit.name), paused"
            : "\(habit.name), \(isCompleted ? "completed" : "not completed")"
    }

    private func accessibilityHint(isCompleted: Bool, isPaused: Bool) -> String {
        if isPaused {
            return "Double tap to resume. Swipe for more actions."
        }
        return isCompleted
            ? "Double tap to mark incomplete. Swipe left to undo."
            : "Double tap to mark complete. Swipe right to mark done."
    }

    private func primaryAccessibilityActionTitle(isCompleted: Bool, isPaused: Bool) -> String {
        isPaused ? "Resume" : (isCompleted ? "Mark incomplete" : "Mark complete")
    }

    private func controlForegroundColor(isCompleted: Bool, isPaused: Bool) -> Color {
        if isPaused  { return .secondary }
        return isCompleted ? .white : .secondary
    }
}

extension HabitRowView: Equatable {
    static func == (lhs: HabitRowView, rhs: HabitRowView) -> Bool {
        lhs.habit == rhs.habit && lhs.isCompletedToday == rhs.isCompletedToday
    }
}

// MARK: - Row Background

private struct HabitRowBackground: View {
    let habit: Habit
    let isCompleted: Bool
    let isPaused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            .fill(isPaused ? Color.todayMutedFill : (isCompleted ? Color.todaySecondaryCardFill : Color.todayCardFill))
            .premiumInteractiveSurface(
                cornerRadius: AppRadius.card,
                tint: habit.tintColor.opacity(isPaused ? 0.03 : (isCompleted ? 0.08 : 0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(
                        Color.todaySurfaceStroke.opacity(isPaused || isCompleted ? 0.42 : 0.58),
                        lineWidth: 0.6
                    )
            }
            .shadow(
                color: .todayShadow.opacity(isPaused || isCompleted ? 0.5 : 1),
                radius: 16,
                y: 10
            )
    }
}

// MARK: - Button Style

private struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.08, blendDuration: 0),
                value: configuration.isPressed
            )
    }
}
