import SwiftUI

struct HistoryView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel = HistoryViewModel()
    @State private var hasAppeared = false
    @State private var ringProgress: CGFloat = 0

    private let horizontalPadding = AppSpacing.screenHorizontal

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView

                if store.habits.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: AppSpacing.section + 4) {
                            Text(weekRangeString)
                                .font(AppType.footnote)
                                .foregroundStyle(.secondary)
                                .opacity(hasAppeared ? 1 : 0)
                                .offset(y: hasAppeared ? 0 : 10)
                            weekRingCard
                            summaryLine
                            habitWeekSection
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, AppSpacing.compact)
                        .padding(.bottom, AppSpacing.screenBottom)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .appScrollChrome()
                }
            }
            .navigationTitle("Reflect")
            .toolbarTitleDisplayMode(.large)
            .task {
                viewModel.refresh(using: store.habits, now: Date())
                guard !hasAppeared else { return }
                if reduceMotion {
                    hasAppeared = true
                    ringProgress = CGFloat(viewModel.practicedDaysLast7)
                } else {
                    withAnimation(.smooth(duration: 0.45)) {
                        hasAppeared = true
                    }
                    // Animate ring after view appears
                    try? await Task.sleep(for: .milliseconds(400))
                    withAnimation(.spring(duration: 1.0, bounce: 0.15)) {
                        ringProgress = CGFloat(viewModel.practicedDaysLast7)
                    }
                }
            }
            .onChange(of: store.habits) {
                viewModel.refresh(using: store.habits, now: Date())
                withAnimation(.spring(duration: 0.6, bounce: 0.12)) {
                    ringProgress = CGFloat(viewModel.practicedDaysLast7)
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        LinearGradient(
            colors: [.todayBackgroundTop, .todayBackgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Week Completion Ring

    private var weekRingCard: some View {
        VStack(spacing: AppSpacing.content + 4) {
            // The ring
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 16)
                    .frame(width: 160, height: 160)

                // Progress arc
                Circle()
                    .trim(from: 0, to: min(ringProgress / 7.0, 1.0))
                    .stroke(
                        AngularGradient(
                            colors: [.accentColor.opacity(0.7), .accentColor, .accentColor.opacity(0.9)],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))

                // Center label
                VStack(spacing: 2) {
                    Text("\(viewModel.practicedDaysLast7)")
                        .font(AppType.metric)
                        .contentTransition(.numericText())

                    Text(viewModel.practicedDaysLast7 == 1 ? "day" : "days")
                        .font(AppType.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(viewModel.practicedDaysLast7) of 7 days with activity")

            // Day dots
            dayDotsRow
        }
        .padding(.vertical, AppSpacing.cardPadding)
        .padding(.horizontal, AppSpacing.cardPadding)
        .background(AppHighlightCardBackground())
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 14)
    }

    // MARK: - Day Dots

    private var dayDotsRow: some View {
        let days = Array(viewModel.recentDays.prefix(7).reversed()) // oldest → newest (left → right)
        let calendar = Calendar.current

        return HStack(spacing: 12) {
            ForEach(days) { day in
                let isToday = calendar.isDateInToday(day.date)
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(day.hasActivity
                                  ? Color.accentColor.opacity(0.85)
                                  : Color.primary.opacity(0.06))
                            .frame(width: 28, height: 28)

                        if day.hasActivity {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        if isToday {
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .frame(width: 34, height: 34)
                        }
                    }

                    Text(shortDayLetter(for: day.date))
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(dayName(for: day.date)). \(day.hasActivity ? "Checked in" : "No activity")")
            }
        }
    }

    // MARK: - Summary Line

    private var summaryLine: some View {
        Text(emotionalSummary)
            .font(AppType.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(hasAppeared ? 1 : 0)
            .accessibilityLabel(emotionalSummary)
    }

    // MARK: - Per-Habit Week Section

    @ViewBuilder
    private var habitWeekSection: some View {
        let activeHabits = store.habits.filter { !$0.isPaused }
        let pausedHabits = store.habits.filter(\.isPaused)

        VStack(alignment: .leading, spacing: 0) {
            if !activeHabits.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("This Week")
                        .padding(.bottom, AppSpacing.compact)

                    ForEach(activeHabits, id: \.id) { habit in
                        habitWeekRow(habit: habit)
                    }
                }
            }

            if !pausedHabits.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Paused")
                        .padding(.top, AppSpacing.content)
                        .padding(.bottom, AppSpacing.compact)

                    ForEach(pausedHabits, id: \.id) { habit in
                        habitWeekRow(habit: habit, isPaused: true)
                    }
                }
            }
        }
        .appCardStyle(compact: true)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
    }

    private func habitWeekRow(habit: Habit, isPaused: Bool = false) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let last7 = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }.reversed()

        return HStack(spacing: AppSpacing.item) {
            // Icon
            ZStack {
                Circle()
                    .fill(habit.tintColor.opacity(isPaused ? 0.08 : 0.14))
                    .frame(width: 38, height: 38)

                Image(systemName: habit.systemIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isPaused ? .secondary : habit.tintColor)
            }

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(AppType.bodyEmphasis)
                    .foregroundStyle(isPaused ? .secondary : .primary)
                    .lineLimit(1)

                if isPaused {
                    Text("Paused")
                        .font(AppType.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            // 7-day dots
            if !isPaused {
                HStack(spacing: 5) {
                    ForEach(Array(last7), id: \.self) { date in
                        let key = PersistenceManager.dateKey(for: date)
                        let done = habit.completions[key] == true
                        Circle()
                            .fill(done ? habit.tintColor.opacity(0.85) : Color.primary.opacity(0.07))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(habitAccessibilityLabel(habit: habit, isPaused: isPaused))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing to reflect on yet",
            systemImage: "book.closed",
            description: Text("Check in today and it'll show up here.")
        )
    }

    // MARK: - Supporting Views

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(AppType.sectionLabel)
            .foregroundStyle(.secondary)
    }

    // MARK: - Copy

    private var emotionalSummary: String {
        let days = viewModel.practicedDaysLast7
        switch days {
        case 0:
            return "Quiet week. Starting again is still starting."
        case 1:
            return "One day this week. That's enough to keep going."
        case 2:
            return "Two days. The rhythm is there, even if it's quiet."
        case 3:
            return "Three days. You're building something real."
        case 4:
            return "Four days. This is what consistency actually looks like."
        case 5:
            return "Five days. These habits are becoming part of your week."
        case 6:
            return "Six out of seven. That's not a streak. That's a life."
        case 7:
            return "Every day this week. Not because you had to."
        default:
            return "Keep going, at your own pace."
        }
    }

    private var weekRangeString: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today) else {
            return ""
        }

        let startStr = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let endStr = today.formatted(.dateTime.month(.abbreviated).day())
        return "\(startStr) – \(endStr)"
    }

    private func shortDayLetter(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private func dayName(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date)     { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    private func habitAccessibilityLabel(habit: Habit, isPaused: Bool) -> String {
        if isPaused {
            return "\(habit.name). Paused."
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let last7 = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
        let doneCount = last7.filter { date in
            let key = PersistenceManager.dateKey(for: date)
            return habit.completions[key] == true
        }.count
        return "\(habit.name). \(doneCount) of 7 days completed."
    }
}
