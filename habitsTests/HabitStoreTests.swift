import Foundation
import Testing
@testable import habits

@MainActor
@Suite("Habit Store", .serialized)
struct HabitStoreTests {
    @Test("Adding, editing, deleting, pausing, and completing habits")
    func habitLifecycle() async throws {
        let fixedDate = self.fixedDate
        let recorder = SaveRecorder()
        let store = HabitStore(
            loadHabits: { .init(habits: [], recovery: .none) },
            saveHabits: { habits, revision in recorder.record(habits, revision: revision) },
            refreshHabits: { .init(habits: [], didChange: false, errorDescription: nil) },
            dateProvider: { fixedDate },
            loadOnInit: false
        )

        let addedHabit = try store.add(draft: HabitDraft(name: "Read", note: "Ten quiet minutes", colorName: "blue", systemIcon: "book")).get()
        #expect(store.habits.count == 1)
        #expect(store.activeHabits.count == 1)

        _ = try store.update(addedHabit, draft: HabitDraft(name: "Read Book", note: "Wind down", colorName: "mint", systemIcon: "moon")).get()
        let updatedHabit = try #require(store.habits.first)
        #expect(updatedHabit.name == "Read Book")
        #expect(updatedHabit.note == "Wind down")
        #expect(updatedHabit.colorName == "mint")

        let completed = store.toggle(updatedHabit)
        #expect(completed)
        #expect(store.isCompletedToday(updatedHabit))
        #expect(store.completedTodayCount == 1)

        store.setPaused(true, for: updatedHabit)
        let pausedHabit = try #require(store.habits.first)
        #expect(pausedHabit.isPaused)
        #expect(store.activeHabits.isEmpty)
        #expect(store.pausedHabits.count == 1)
        #expect(store.toggle(pausedHabit) == false)

        store.setPaused(false, for: pausedHabit)
        store.delete(pausedHabit)
        await store.awaitPendingOperations()
        #expect(store.habits.isEmpty)
        #expect(recorder.savedSnapshots.count >= 5)
    }

    @Test("Validation prevents duplicates and empty names")
    func validation() async {
        let store = HabitStore(
            loadHabits: { .init(habits: [], recovery: .none) },
            saveHabits: { habits, revision in .init(habits: habits, errorDescription: nil, revision: revision) },
            refreshHabits: { .init(habits: [], didChange: false, errorDescription: nil) },
            loadOnInit: false
        )

        _ = store.add(draft: HabitDraft(name: "Walk", note: "", colorName: "green", systemIcon: "figure.walk"))

        let emptyResult = store.add(draft: HabitDraft(name: "   ", note: "", colorName: "green", systemIcon: "circle"))
        let duplicateResult = store.add(draft: HabitDraft(name: "walk", note: "", colorName: "blue", systemIcon: "circle"))

        await store.awaitPendingOperations()
        #expect(emptyResult == .failure(.emptyName))
        #expect(duplicateResult == .failure(.duplicateName))
    }

    @Test("Reflection days reflect tracked completions")
    func reflectionDays() async throws {
        let fixedDate = self.fixedDate
        let todayKey = PersistenceManager.dateKeyFormatter.string(from: fixedDate)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: fixedDate) ?? fixedDate
        let yesterdayKey = PersistenceManager.dateKeyFormatter.string(from: yesterday)
        let store = HabitStore(
            loadHabits: { .init(habits: [], recovery: .none) },
            saveHabits: { habits, revision in .init(habits: habits, errorDescription: nil, revision: revision) },
            refreshHabits: { .init(habits: [], didChange: false, errorDescription: nil) },
            dateProvider: { fixedDate },
            loadOnInit: false
        )
        store.habits = [
            Habit(
                name: "Read",
                colorName: "blue",
                systemIcon: "book",
                completions: [todayKey: true, yesterdayKey: true],
                createdAt: yesterday
            ),
            Habit(
                name: "Walk",
                colorName: "green",
                systemIcon: "figure.walk",
                completions: [todayKey: true],
                createdAt: yesterday
            )
        ]
        let days = store.reflectionDays(limit: 2)
        let first = try #require(days.first)
        #expect(first.completed == 2)
        #expect(first.activeHabitCount == 2)
        #expect(first.habitNames == ["Read", "Walk"])
        let last = try #require(days.last)
        #expect(last.completed == 1)
    }

    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_734_739_200)
    }
}

private final class SaveRecorder: @unchecked Sendable {
    private(set) var savedSnapshots: [[Habit]] = []

    func record(_ habits: [Habit], revision: Int) -> HabitStore.RepositorySaveResult {
        savedSnapshots.append(habits)
        return .init(habits: habits, errorDescription: nil, revision: revision)
    }
}
