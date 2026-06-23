import SwiftUI

struct TodayView: View {

    @Environment(HabitStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingAddSheet    = false
    @State private var habitToEdit:   Habit?
    @State private var habitToDelete: Habit?
    @State private var hasAppeared = false
    @State private var toastItem: TodayToast?

    private let horizontalPadding = AppSpacing.screenHorizontal
    private let sectionSpacing    = AppSpacing.section
    private let habitCardSpacing  = AppSpacing.item

    private var rowSpring: Animation? {
        reduceMotion ? nil : .spring(duration: 0.52, bounce: 0.18, blendDuration: 0)
    }

    var body: some View {
        let activeHabits  = store.activeHabits
        let pausedHabits  = store.pausedHabits
        let completedIDs  = Set(
            store.habits.lazy.compactMap { h in
                (h.completions[store.todayKey] ?? false) ? h.id : nil
            }
        )

        NavigationStack {
            ZStack {
                backgroundGradient

                List {
                    // Hero
                    Section {
                        heroSection
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: AppSpacing.screenTop,
                        leading: horizontalPadding,
                        bottom: 0,
                        trailing: horizontalPadding
                    ))

                    // Habit list
                    if store.habits.isEmpty {
                        Section {
                            emptyStateSection
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: AppSpacing.item,
                            leading: horizontalPadding,
                            bottom: 0,
                            trailing: horizontalPadding
                        ))
                    } else {
                        if !activeHabits.isEmpty {
                            Section {
                                ForEach(activeHabits, id: \.id) { habit in
                                    HabitRowView(
                                        habit: habit,
                                        isCompletedToday: completedIDs.contains(habit.id),
                                        onPrimaryAction: {
                                            if habit.isPaused {
                                                store.setPaused(false, for: habit)
                                            } else {
                                                _ = store.toggle(habit)
                                            }
                                        },
                                        onPauseToggle: {
                                            store.setPaused(!habit.isPaused, for: habit)
                                        },
                                        onEdit: {
                                            habitToEdit = habit
                                            HapticManager.shared.play(.openComposer)
                                        },
                                        onDelete: {
                                            habitToDelete = habit
                                        }
                                    )
                                    .equatable()
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(
                                        top:     habitCardSpacing / 2,
                                        leading: horizontalPadding,
                                        bottom:  habitCardSpacing / 2,
                                        trailing: horizontalPadding
                                    ))
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        if !habit.isPaused {
                                            let isDone = completedIDs.contains(habit.id)
                                            Button {
                                                _ = store.toggle(habit)
                                                HapticManager.shared.play(isDone ? .habitUnchecked : .habitCompleted)
                                            } label: {
                                                Label(
                                                    isDone ? "Undo" : "Done",
                                                    systemImage: isDone ? "arrow.uturn.backward" : "checkmark"
                                                )
                                            }
                                            .tint(isDone ? .pauseControlTint : .habitDoneAccent)
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            habitToDelete = habit
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }

                                        Button {
                                            store.setPaused(!habit.isPaused, for: habit)
                                            HapticManager.shared.play(.pauseStateChanged)
                                        } label: {
                                            Label(
                                                habit.isPaused ? "Resume" : "Pause",
                                                systemImage: habit.isPaused ? "play.fill" : "pause.fill"
                                            )
                                        }
                                        .tint(.pauseControlTint)

                                        Button {
                                            habitToEdit = habit
                                            HapticManager.shared.play(.openComposer)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                    }
                                }
                            }
                            .listRowSeparator(.hidden)
                        } else {
                            Section {
                                pausedEmptyStateSection
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(
                                top: AppSpacing.item,
                                leading: horizontalPadding,
                                bottom: 0,
                                trailing: horizontalPadding
                            ))
                        }

                        if !pausedHabits.isEmpty {
                            Section {
                                ForEach(pausedHabits, id: \.id) { habit in
                                    HabitRowView(
                                        habit: habit,
                                        isCompletedToday: completedIDs.contains(habit.id),
                                        onPrimaryAction: {
                                            store.setPaused(false, for: habit)
                                        },
                                        onPauseToggle: {
                                            store.setPaused(false, for: habit)
                                        },
                                        onEdit: {
                                            habitToEdit = habit
                                            HapticManager.shared.play(.openComposer)
                                        },
                                        onDelete: {
                                            habitToDelete = habit
                                        }
                                    )
                                    .equatable()
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(
                                        top:     habitCardSpacing / 2,
                                        leading: horizontalPadding,
                                        bottom:  habitCardSpacing / 2,
                                        trailing: horizontalPadding
                                    ))
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            habitToDelete = habit
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }

                                        Button {
                                            store.setPaused(false, for: habit)
                                            HapticManager.shared.play(.pauseStateChanged)
                                        } label: {
                                            Label("Resume", systemImage: "play.fill")
                                        }
                                        .tint(.habitDoneAccent)

                                        Button {
                                            habitToEdit = habit
                                            HapticManager.shared.play(.openComposer)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                    }
                                }
                            } header: {
                                Text("Paused")
                                    .font(AppType.sectionLabel)
                                    .tracking(1.2)
                                    .textCase(.uppercase)
                                    .padding(.leading, horizontalPadding)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .listSectionSpacing(sectionSpacing)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, 100, for: .scrollContent)
                .appScrollChrome()

                // MARK: - Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fabButton
                    }
                    .padding(.trailing, horizontalPadding + 4)
                    .padding(.bottom, AppSpacing.cardStack)
                }
            }
            .overlay(alignment: .top) {
                if let toastItem {
                    TodayToastView(toast: toastItem)
                        .padding(.top, 12)
                        .padding(.horizontal, horizontalPadding)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityAction(named: Text("Dismiss")) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                self.toastItem = nil
                            }
                        }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddSheet) {
                AddHabitSheet(isPresented: $showingAddSheet)
                    .environment(store)
                    .interactiveDismissDisabled(false)
            }
            .sheet(item: $habitToEdit) { habit in
                EditHabitSheet(
                    isPresented: Binding(
                        get: { habitToEdit != nil },
                        set: { if !$0 { habitToEdit = nil } }
                    ),
                    habit: habit
                )
                .environment(store)
            }
            .task {
                guard !hasAppeared else { return }
                if reduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(.spring(duration: 0.6, bounce: 0.16, blendDuration: 0)) {
                        hasAppeared = true
                    }
                }
            }
            .alert(
                "Remove this habit?",
                isPresented: deleteConfirmationBinding
            ) {
                Button("Remove", role: .destructive) {
                    if let habitToDelete {
                        withAnimation(rowSpring) {
                            store.delete(habitToDelete)
                        }
                        HapticManager.shared.play(.destructiveDelete)
                    }
                    self.habitToDelete = nil
                }
                Button("Keep it", role: .cancel) {
                    habitToDelete = nil
                }
            } message: {
                Text(habitToDelete.map { "\"\($0.name)\" will be removed." } ?? "")
            }
            .onChange(of: store.persistenceRecoveryMessage) { _, message in
                guard let message else { return }
                presentToast(title: "Habits Refreshed", message: message, tone: .info)
                store.dismissPersistenceMessage()
                HapticManager.shared.play(.validationWarning)
            }
            .onChange(of: store.lastSaveErrorMessage) { _, message in
                guard let message else { return }
                presentToast(title: "Change Not Saved", message: message, tone: .warning)
                store.dismissSaveErrorMessage()
                HapticManager.shared.play(.operationError)
            }
            .onChange(of: store.lastRefreshErrorMessage) { _, _ in
                HapticManager.shared.play(.operationError)
            }
            .task(id: toastItem?.id) {
                guard toastItem != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    toastItem = nil
                }
            }
        }
    }

    // MARK: - Floating Action Button

    @ViewBuilder
    private var fabButton: some View {
        if #available(iOS 26, *) {
            Button {
                presentAddHabitSheet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(18)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.accentColor)
            .accessibilityLabel("Add habit")
            .accessibilityHint("Opens the new habit form.")
            .scaleEffect(hasAppeared ? 1 : 0)
            .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.3), value: hasAppeared)
        } else {
            Button {
                presentAddHabitSheet()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 60, height: 60)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 14, y: 6)
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(FABButtonStyle())
            .accessibilityLabel("Add habit")
            .accessibilityHint("Opens the new habit form.")
            .scaleEffect(hasAppeared ? 1 : 0)
            .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.3), value: hasAppeared)
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [.todayBackgroundTop, .todayBackgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine.uppercased())
                    .font(AppType.sectionLabel)
                    .foregroundStyle(.secondary)

                Text(greetingLine)
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
            }

            Text(store.ritualSummaryLine)
                .font(AppType.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.35), value: store.ritualSummaryLine)
                .padding(.top, 10)

            if !store.activeHabits.isEmpty {
                progressSection
                    .padding(.top, 14)
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
    }

    // MARK: - Progress Bar

    private var progressSection: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 6)

                Capsule()
                    .fill(LinearGradient(
                        colors: store.allHabitsCompleteToday
                            ? [.habitDoneAccent.opacity(0.7), .habitDoneAccent.opacity(0.5)]
                            : [.accentColor.opacity(0.6), .accentColor.opacity(0.45)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(
                        width: max(proxy.size.width * store.todayProgress,
                                   store.todayProgress > 0 ? 10 : 0),
                        height: 6
                    )
                    .animation(rowSpring, value: store.todayProgress)
                    .animation(.spring(duration: 0.5), value: store.allHabitsCompleteToday)
            }
        }
        .frame(height: 6)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.completedTodayCount) of \(store.activeHabits.count) habits complete")
    }

    // MARK: - Empty States

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.content) {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("Add your first habit")
                    .font(AppType.sectionTitle)

                Text("Small enough that you'd do it even on a hard day.")
                    .font(AppType.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                presentAddHabitSheet()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(AppType.iconSmall)
                    Text("Begin a Habit")
                        .font(AppType.bodyEmphasis)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(AppType.caption)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(.clear)
                    .premiumInteractiveSurface(cornerRadius: AppRadius.control)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardStyle()
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add your first habit. Small enough that you'd do it even on a hard day.")
        .accessibilityHint("Tap Begin a Habit to get started.")
    }

    private var pausedEmptyStateSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("All habits paused")
                .font(AppType.sectionTitle)

            Text("Resume any habit from the list below whenever you're ready.")
                .font(AppType.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All habits paused. Resume any habit from the list below.")
    }

    // MARK: - Helpers

    private var greetingLine: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    private var dateLine: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func presentAddHabitSheet() {
        showingAddSheet = true
        HapticManager.shared.play(.openComposer)
    }

    private func presentToast(title: String, message: String, tone: TodayToast.Tone) {
        withAnimation(.spring(duration: 0.35, bounce: 0.18, blendDuration: 0)) {
            toastItem = TodayToast(title: title, message: message, tone: tone)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { habitToDelete != nil },
            set: { if !$0 { habitToDelete = nil } }
        )
    }
}

// MARK: - FAB Button Style

private struct FABButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.1),
                value: configuration.isPressed
            )
    }
}

// MARK: - Toast Model

private struct TodayToast: Identifiable, Equatable {
    enum Tone: Equatable {
        case info
        case warning

        var accentColor: Color {
            switch self {
            case .info:    return .toastInfoAccent
            case .warning: return .toastWarningAccent
            }
        }

        var systemImage: String {
            switch self {
            case .info:    return "checkmark.circle.fill"
            case .warning: return "exclamationmark.circle.fill"
            }
        }
    }

    let id      = UUID()
    let title:   String
    let message: String
    let tone:    Tone
}

// MARK: - Toast View

private struct TodayToastView: View {
    let toast: TodayToast

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: toast.tone.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(toast.tone.accentColor)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .font(AppType.captionStrong)
                    .foregroundStyle(.primary)

                Text(toast.message)
                    .font(AppType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial,
                     in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.todayStrongStroke, lineWidth: 0.5)
        }
        .shadow(color: .todayShadow, radius: 12, y: 6)
    }
}
