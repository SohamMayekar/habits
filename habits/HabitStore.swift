import Foundation
import SwiftUI

@MainActor
@Observable
final class HabitStore {
    struct RepositoryLoadResult: Sendable {
        let habits: [Habit]
        let recovery: PersistenceManager.LoadResult.Recovery
    }

    struct RepositorySaveResult: Sendable {
        let habits: [Habit]
        let errorDescription: String?
        let revision: Int
    }

    struct RepositoryRefreshResult: Sendable {
        let habits: [Habit]
        let didChange: Bool
        let errorDescription: String?
    }

    enum MutationError: LocalizedError, Equatable, Sendable {
        case emptyName
        case duplicateName
        case nameTooLong
        case noteTooLong

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return String(localized: "Choose a short name for this habit.")
            case .duplicateName:
                return String(localized: "This habit already exists. Try a different name.")
            case .nameTooLong:
                return String(localized: "Habit names can be up to 40 characters.")
            case .noteTooLong:
                return String(localized: "Notes can be up to 120 characters.")
            }
        }
    }

    struct DayEntry: Identifiable, Sendable {
        let id: String
        let date: Date
        let completed: Int
        let habitNames: [String]
        let activeHabitCount: Int

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

        var hasActivity: Bool {
            completed > 0
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

    typealias Loader = @Sendable () async -> RepositoryLoadResult
    typealias Saver = @Sendable ([Habit], Int) async -> RepositorySaveResult
    typealias Refresher = @Sendable () async -> RepositoryRefreshResult
    typealias DateProvider = @Sendable () -> Date

    var habits: [Habit] = []
    var isLoading = true
    var isRefreshing = false
    var persistenceRecoveryMessage: String?
    var lastSaveErrorMessage: String?
    var lastRefreshErrorMessage: String?

    private let loadHabits: Loader
    private let saveHabits: Saver
    private let refreshHabits: Refresher
    private let dateProvider: DateProvider
    private var persistTask: Task<Void, Never>?
    private var refreshTask: Task<RepositoryRefreshResult, Never>?
    private var currentRevision = 0
    private var hasLoadedInitialState = false
    private var loadedContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        loadHabits: @escaping Loader,
        saveHabits: @escaping Saver,
        refreshHabits: @escaping Refresher,
        dateProvider: @escaping DateProvider = Date.init,
        loadOnInit: Bool = true
    ) {
        self.loadHabits = loadHabits
        self.saveHabits = saveHabits
        self.refreshHabits = refreshHabits
        self.dateProvider = dateProvider

        guard loadOnInit else {
            isLoading = false
            return
        }

        Task {
            await load()
        }
    }

    convenience init(
        repository: HabitRepository,
        dateProvider: @escaping DateProvider = Date.init,
        loadOnInit: Bool = true
    ) {
        self.init(
            loadHabits: {
                let result = await repository.load()
                return RepositoryLoadResult(habits: result.habits, recovery: result.recovery)
            },
            saveHabits: { habits, revision in
                let result = await repository.saveSnapshot(habits, revision: revision)
                return RepositorySaveResult(
                    habits: result.habits,
                    errorDescription: result.errorDescription,
                    revision: result.revision
                )
            },
            refreshHabits: {
                let result = await repository.refreshFromRemote()
                return RepositoryRefreshResult(
                    habits: result.habits,
                    didChange: result.didChange,
                    errorDescription: result.errorDescription
                )
            },
            dateProvider: dateProvider,
            loadOnInit: loadOnInit
        )
    }

    var todayKey: String {
        PersistenceManager.dateKeyFormatter.string(from: dateProvider())
    }

    var activeHabits: [Habit] {
        habits.filter { !$0.isPaused }
    }

    var pausedHabits: [Habit] {
        habits.filter(\.isPaused)
    }

    var todayProgress: Double {
        guard !activeHabits.isEmpty else { return 0 }
        return Double(completedTodayCount) / Double(activeHabits.count)
    }

    var completedTodayCount: Int {
        activeHabits.filter { isCompletedToday($0) }.count
    }

    var remainingTodayCount: Int {
        max(activeHabits.count - completedTodayCount, 0)
    }

    /// True when every active habit is checked off today.
    var allHabitsCompleteToday: Bool {
        !activeHabits.isEmpty && completedTodayCount == activeHabits.count
    }

    /// Full calendar days since the user last completed any habit.
    /// 0 means there is activity today. 61 means no history found.
    var daysSinceLastActivity: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: dateProvider())
        for offset in 0...60 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            let key = PersistenceManager.dateKeyFormatter.string(from: date)
            if habits.contains(where: { $0.completions[key] == true }) { return offset }
        }
        return habits.isEmpty ? 0 : 61
    }

    /// A single human line shown below the greeting on the Today screen.
    var ritualSummaryLine: String {
        if activeHabits.isEmpty {
            return pausedHabits.isEmpty
                ? String(localized: "A new day.")
                : String(localized: "Your habits are paused.")
        }

        if allHabitsCompleteToday {
            return String(localized: "All done for today.")
        }

        let gap = daysSinceLastActivity
        if gap >= 8 {
            return String(localized: "Good to have you back.")
        } else if gap >= 5 {
            return String(localized: "It’s been a while. Today is enough.")
        } else if gap >= 3 {
            return String(localized: "Welcome back.")
        } else if gap == 2 {
            return String(localized: "Two days away. You’re back now.")
        }

        if completedTodayCount == 0 {
            return String(localized: "Ready when you are.")
        }

        return String(localized: "Keep going.")
    }
    func dateKey(for date: Date) -> String {
        PersistenceManager.dateKeyFormatter.string(from: date)
    }

    func dismissPersistenceMessage() {
        persistenceRecoveryMessage = nil
    }

    func dismissSaveErrorMessage() {
        lastSaveErrorMessage = nil
    }

    func dismissRefreshErrorMessage() {
        lastRefreshErrorMessage = nil
    }

    func retryRefresh() async {
        await refreshFromRemote()
    }

    func awaitLoaded() async {
        guard isLoading else { return }
        await withCheckedContinuation { continuation in
            loadedContinuations.append(continuation)
        }
    }

    func load() async {
        guard !hasLoadedInitialState else { return }

        let result = await loadHabits()
        habits = result.habits.sorted { habitSort(lhs: $0, rhs: $1) }
        persistenceRecoveryMessage = recoveryMessage(for: result.recovery)
        isLoading = false
        hasLoadedInitialState = true

        for continuation in loadedContinuations {
            continuation.resume()
        }
        loadedContinuations.removeAll()

        await refreshFromRemote()
    }

    func awaitPendingOperations() async {
        await persistTask?.value
        _ = await refreshTask?.value
    }

    func isCompletedToday(_ habit: Habit) -> Bool {
        habit.completions[todayKey] ?? false
    }

    @discardableResult
    func toggle(_ habit: Habit) -> Bool {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else {
            return false
        }
        guard !habits[index].isPaused else {
            return false
        }

        let wasCompleted = habits[index].completions[todayKey] ?? false
        habits[index].completions[todayKey] = !wasCompleted
        persist()
        return !wasCompleted
    }

    func add(draft: HabitDraft) -> Result<Habit, MutationError> {
        switch validate(draft: draft, excluding: nil) {
        case .success(let normalizedDraft):
            let newHabit = Habit(
                name: normalizedDraft.trimmedName,
                note: normalizedDraft.trimmedNote,
                colorName: normalizedDraft.colorName,
                systemIcon: normalizedDraft.systemIcon
            )
            habits.append(newHabit)
            habits.sort { habitSort(lhs: $0, rhs: $1) }
            persist()
            return .success(newHabit)
        case .failure(let error):
            return .failure(error)
        }
    }

    func add(name: String, note: String = "", colorName: String, systemIcon: String = "circle") {
        _ = add(draft: HabitDraft(name: name, note: note, colorName: colorName, systemIcon: systemIcon))
    }

    func delete(_ habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        habits.remove(atOffsets: offsets)
        persist()
    }

    @discardableResult
    func update(_ habit: Habit, draft: HabitDraft) -> Result<Void, MutationError> {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else {
            return .success(())
        }

        switch validate(draft: draft, excluding: habit.id) {
        case .success(let normalizedDraft):
            habits[index].name = normalizedDraft.trimmedName
            habits[index].note = normalizedDraft.trimmedNote
            habits[index].colorName = normalizedDraft.colorName
            habits[index].systemIcon = normalizedDraft.systemIcon
            habits.sort { habitSort(lhs: $0, rhs: $1) }
            persist()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func update(_ habit: Habit, name: String, note: String, colorName: String, systemIcon: String) {
        _ = update(habit, draft: HabitDraft(name: name, note: note, colorName: colorName, systemIcon: systemIcon))
    }

    func seedIfEmpty(with habits: [Habit]) {
        guard self.habits.isEmpty, habits.isEmpty == false else { return }
        self.habits = habits.sorted { habitSort(lhs: $0, rhs: $1) }
        persist()
    }

    func setPaused(_ paused: Bool, for habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].isPaused = paused
        persist()
    }

    func deleteAll() {
        habits.removeAll()
        persist()
    }

    func validationMessage(for draft: HabitDraft, excluding habitID: UUID? = nil) -> String? {
        switch validate(draft: draft, excluding: habitID) {
        case .success:
            return nil
        case .failure(let error):
            return error.errorDescription
        }
    }

    func reflectionDays(limit: Int = 7) -> [DayEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: dateProvider())
        let earliestTrackedDay = earliestTrackedDate ?? today

        let allTrackedDays = stride(from: 0, through: 365, by: 1).compactMap { offset -> Date? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return date >= earliestTrackedDay ? date : nil
        }

        return allTrackedDays.prefix(limit).map { date in
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

    func completionCount(forDateKey key: String) -> Int {
        habits.filter { $0.completions[key] == true }.count
    }

    func completionCount(for date: Date) -> Int {
        completionCount(forDateKey: dateKey(for: date))
    }

    func recentDays(count: Int) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: dateProvider())

        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    func practicedDayCount(days: Int) -> Int {
        reflectionDays(limit: days).filter(\.hasActivity).count
    }

    func totalCompletions(days: Int) -> Int {
        reflectionDays(limit: days).reduce(0) { $0 + $1.completed }
    }

    func habitRhythms(days: Int = 14) -> [HabitRhythm] {
        let calendar = Calendar.current
        let recentDates = recentDays(count: days).reversed()

        return habits.compactMap { habit in
            let trackableDates = recentDates.filter { date in
                calendar.startOfDay(for: habit.createdAt) <= calendar.startOfDay(for: date)
            }

            guard !trackableDates.isEmpty else { return nil }

            let completedDates = trackableDates.filter { date in
                habit.completions[dateKey(for: date)] == true
            }

            let lastCompletedDate = completedDates.last

            return HabitRhythm(
                id: habit.id,
                habit: habit,
                completedDays: completedDates.count,
                trackedDays: trackableDates.count,
                lastCompletedDate: lastCompletedDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.completedDays != rhs.completedDays {
                return lhs.completedDays > rhs.completedDays
            }

            return lhs.habit.trimmedName.localizedCaseInsensitiveCompare(rhs.habit.trimmedName) == .orderedAscending
        }
    }

    private func validate(draft: HabitDraft, excluding habitID: UUID?) -> Result<HabitDraft, MutationError> {
        let normalized = HabitDraft(
            name: draft.trimmedName,
            note: draft.trimmedNote,
            colorName: draft.colorName,
            systemIcon: draft.systemIcon
        )

        guard !normalized.trimmedName.isEmpty else {
            return .failure(.emptyName)
        }

        guard normalized.trimmedName.count <= Habit.maxNameLength else {
            return .failure(.nameTooLong)
        }

        guard normalized.trimmedNote.count <= Habit.maxNoteLength else {
            return .failure(.noteTooLong)
        }

        let normalizedName = normalized.trimmedName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let duplicateExists = habits.contains { habit in
            habit.id != habitID &&
            habit.trimmedName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalizedName
        }

        guard !duplicateExists else {
            return .failure(.duplicateName)
        }

        return .success(normalized)
    }

    private var earliestTrackedDate: Date? {
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

    private func persist() {
        currentRevision += 1
        let revision = currentRevision
        let snapshot = habits

        persistTask?.cancel()
        persistTask = Task { [saveHabits] in
            let result = await saveHabits(snapshot, revision)
            guard !Task.isCancelled else { return }
            applyPersistResult(result, expectedRevision: revision)
        }
    }

    func refreshFromRemote() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let requestedRevision = currentRevision
        let task = Task { [refreshHabits] in
            await refreshHabits()
        }

        refreshTask?.cancel()
        refreshTask = task

        let result = await task.value
        guard !Task.isCancelled, requestedRevision == currentRevision else { return }

        lastRefreshErrorMessage = result.errorDescription.map { _ in
            String(localized: "Fresh habit data could not be downloaded right now.")
        }

        guard result.didChange else { return }

        withAnimation(.smooth(duration: 0.3)) {
            habits = result.habits.sorted { habitSort(lhs: $0, rhs: $1) }
        }
    }

    private func applyPersistResult(_ result: RepositorySaveResult, expectedRevision: Int) {
        guard expectedRevision == currentRevision else { return }

        habits = result.habits.sorted { habitSort(lhs: $0, rhs: $1) }
        lastSaveErrorMessage = result.errorDescription.map { _ in
            String(localized: "Your last change could not be saved. Try again in a moment.")
        }
    }

    private func recoveryMessage(for recovery: PersistenceManager.LoadResult.Recovery) -> String? {
        switch recovery {
        case .none:
            return nil
        case .migratedLegacyFile:
            return String(localized: "Your habits were updated to the latest local format.")
        case .recoveredFromCorruption:
            return String(localized: "A damaged habits file was set aside so the app could open safely.")
        }
    }

    private func habitSort(lhs: Habit, rhs: Habit) -> Bool {
        if lhs.isPaused != rhs.isPaused {
            return rhs.isPaused
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.trimmedName.localizedCaseInsensitiveCompare(rhs.trimmedName) == .orderedAscending
    }
}
