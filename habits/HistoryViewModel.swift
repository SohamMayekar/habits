import Foundation
import SwiftUI

@MainActor
@Observable
final class HistoryViewModel {
    struct DayEntry: Identifiable, Sendable {
        let id: String
        let date: Date
        let completed: Int
        let habitNames: [String]
        let activeHabitCount: Int

        var hasActivity: Bool {
            completed > 0
        }

        var reflectionLine: String {
            switch completed {
            case 0:
                return String(localized: "No habits were checked off.")
            case 1:
                return String(localized: "One habit was checked off.")
            default:
                return String(localized: "\(completed) habits were checked off.")
            }
        }
    }

    struct HabitRhythm: Identifiable, Sendable {
        let id: UUID
        let habit: Habit
        let completedDays: Int
        let trackedDays: Int
        let lastCompletedDate: Date?

        var completionRate: Double {
            guard trackedDays > 0 else { return 0 }
            return Double(completedDays) / Double(trackedDays)
        }
    }

    var recentDays: [DayEntry] = []
    var habitRhythms: [HabitRhythm] = []
    var practicedDaysLast7 = 0
    var practicedDaysLast14 = 0
    var totalCompletionsLast7 = 0

    private var rebuildTask: Task<Void, Never>?
    private var generation = 0

    func refresh(using habits: [Habit], now: Date) {
        generation += 1
        let generation = generation

        rebuildTask?.cancel()
        rebuildTask = Task(priority: .utility) {
            let snapshot = await Self.buildSnapshot(habits: habits, now: now)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == self.generation else { return }
                self.recentDays = snapshot.recentDays
                self.habitRhythms = snapshot.habitRhythms
                self.practicedDaysLast7 = snapshot.practicedDaysLast7
                self.practicedDaysLast14 = snapshot.practicedDaysLast14
                self.totalCompletionsLast7 = snapshot.totalCompletionsLast7
            }
        }
    }

    private struct Snapshot: Sendable {
        let recentDays: [DayEntry]
        let habitRhythms: [HabitRhythm]
        let practicedDaysLast7: Int
        let practicedDaysLast14: Int
        let totalCompletionsLast7: Int
    }

    private nonisolated static func buildSnapshot(habits: [Habit], now: Date) async -> Snapshot {
        await Task.detached(priority: .utility) {
            let recentDays = makeRecentDays(habits: habits, now: now, count: 14)
            let habitRhythms = makeHabitRhythms(habits: habits, now: now, days: 14)

            return Snapshot(
                recentDays: recentDays,
                habitRhythms: habitRhythms,
                practicedDaysLast7: recentDays.prefix(7).filter { $0.completed > 0 }.count,
                practicedDaysLast14: recentDays.prefix(14).filter { $0.completed > 0 }.count,
                totalCompletionsLast7: recentDays.prefix(7).reduce(0) { $0 + $1.completed }
            )
        }.value
    }

    private nonisolated static func makeRecentDays(habits: [Habit], now: Date, count: Int) -> [DayEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let earliestTrackedDay = earliestTrackedDate(habits: habits) ?? today

        return (0..<count).compactMap { offset -> DayEntry? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today), date >= earliestTrackedDay else {
                return nil
            }

            let key = dateKey(for: date)
            let habitsExistingThatDay = habits.filter { habit in
                calendar.startOfDay(for: habit.createdAt) <= date
            }
            let completedHabits = habitsExistingThatDay.filter { $0.completions[key] == true }

            return DayEntry(
                id: key,
                date: date,
                completed: completedHabits.count,
                habitNames: completedHabits.map(\.name),
                activeHabitCount: habitsExistingThatDay.count
            )
        }
    }

    private nonisolated static func makeHabitRhythms(habits: [Habit], now: Date, days: Int) -> [HabitRhythm] {
        let calendar = Calendar.current
        let recentDates = (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))
        }.reversed()

        return habits.compactMap { habit in
            let trackableDates = recentDates.filter { date in
                calendar.startOfDay(for: habit.createdAt) <= calendar.startOfDay(for: date)
            }

            guard !trackableDates.isEmpty else { return nil }

            let completedDates = trackableDates.filter { date in
                habit.completions[dateKey(for: date)] == true
            }

            return HabitRhythm(
                id: habit.id,
                habit: habit,
                completedDays: completedDates.count,
                trackedDays: trackableDates.count,
                lastCompletedDate: completedDates.last
            )
        }
        .sorted { lhs, rhs in
            if lhs.completedDays != rhs.completedDays {
                return lhs.completedDays > rhs.completedDays
            }

            return lhs.habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(
                    rhs.habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                ) == .orderedAscending
        }
    }

    private nonisolated static func earliestTrackedDate(habits: [Habit]) -> Date? {
        let calendar = Calendar.current
        let createdDates = habits.map { calendar.startOfDay(for: $0.createdAt) }
        let completionDates = habits.flatMap { habit in
            habit.completions.compactMap { key, value -> Date? in
                guard value else { return nil }
                return PersistenceManager.date(fromDateKey: key).map { calendar.startOfDay(for: $0) }
            }
        }

        return (createdDates + completionDates).min()
    }

    private nonisolated static func dateKey(for date: Date) -> String {
        PersistenceManager.dateKey(for: date)
    }
}
