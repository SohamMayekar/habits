import Foundation
import SwiftData

@Model
final class HabitRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var note: String
    var colorName: String
    var systemIcon: String
    var completionsData: Data
    var isPaused: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var needsLocalProtection: Bool

    init(
        id: UUID,
        name: String,
        note: String,
        colorName: String,
        systemIcon: String,
        completionsData: Data,
        isPaused: Bool,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        needsLocalProtection: Bool = false
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.colorName = colorName
        self.systemIcon = systemIcon
        self.completionsData = completionsData
        self.isPaused = isPaused
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.needsLocalProtection = needsLocalProtection
    }
}

struct RemoteHabitSnapshot: Codable, Sendable {
    let habits: [RemoteHabit]
}

struct RemoteHabit: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let note: String
    let colorName: String
    let systemIcon: String
    let completions: [String: Bool]
    let isPaused: Bool
    let createdAt: Date
    let updatedAt: Date
}

protocol HabitRemoteDataSource: Sendable {
    func fetchHabits() async throws -> [RemoteHabit]?
}

struct EmptyHabitRemoteDataSource: HabitRemoteDataSource {
    nonisolated init() {}

    func fetchHabits() async throws -> [RemoteHabit]? {
        nil
    }
}

struct URLSessionHabitRemoteDataSource: HabitRemoteDataSource {
    let endpoint: URL?
    var session: URLSession = .shared

    func fetchHabits() async throws -> [RemoteHabit]? {
        guard let endpoint else {
            return nil
        }

        let (data, response) = try await session.data(from: endpoint)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let snapshot = try? decoder.decode(RemoteHabitSnapshot.self, from: data) {
            return snapshot.habits
        }

        return try decoder.decode([RemoteHabit].self, from: data)
    }
}

actor HabitRepository {
    struct LoadResult: Sendable {
        let habits: [Habit]
        let recovery: PersistenceManager.LoadResult.Recovery
    }

    struct SaveResult: Sendable {
        let habits: [Habit]
        let errorDescription: String?
        let revision: Int
    }

    struct RefreshResult: Sendable {
        let habits: [Habit]
        let didChange: Bool
        let errorDescription: String?
    }

    let container: ModelContainer

    private let modelContext: ModelContext
    private let remoteDataSource: any HabitRemoteDataSource
    private let dateProvider: @Sendable () -> Date

    private var latestPersistedRevision = -1

    init(
        container: ModelContainer,
        remoteDataSource: any HabitRemoteDataSource,
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.container = container
        self.modelContext = ModelContext(container)
        self.remoteDataSource = remoteDataSource
        self.dateProvider = dateProvider
        self.modelContext.autosaveEnabled = false
    }

    nonisolated static func makeDefault(
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) -> HabitRepository {
        let configuration = ModelConfiguration("HabitsCache")
        let container: ModelContainer

        do {
            container = try ModelContainer(for: HabitRecord.self, configurations: configuration)
        } catch {
            // Fall back to an in-memory container so the app can still launch
            let inMemory = ModelConfiguration("HabitsCache", isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: HabitRecord.self, configurations: inMemory))
                ?? (try! ModelContainer(for: HabitRecord.self))
        }

        let remoteDataSource: any HabitRemoteDataSource
        if let endpoint = AppSupport.habitsFeedURL {
            remoteDataSource = URLSessionHabitRemoteDataSource(endpoint: endpoint)
        } else {
            remoteDataSource = EmptyHabitRemoteDataSource()
        }
        return HabitRepository(
            container: container,
            remoteDataSource: remoteDataSource,
            dateProvider: dateProvider
        )
    }

    func load() -> LoadResult {
        do {
            if try fetchRecordCount() == 0 {
                let legacyLoad = PersistenceManager.load(environment: PersistenceManager.environment)
                let recoveredFromLegacy: Bool
                switch legacyLoad.recovery {
                case .none:
                    recoveredFromLegacy = false
                case .migratedLegacyFile, .recoveredFromCorruption:
                    recoveredFromLegacy = true
                }

                if !legacyLoad.habits.isEmpty || recoveredFromLegacy {
                    try replaceCache(with: legacyLoad.habits, protectsLocalEdits: false)
                    return LoadResult(habits: legacyLoad.habits, recovery: legacyLoad.recovery)
                }
            }

            return LoadResult(habits: try fetchVisibleHabits(), recovery: .none)
        } catch {
            let legacyLoad = PersistenceManager.load(environment: PersistenceManager.environment)
            return LoadResult(habits: legacyLoad.habits, recovery: legacyLoad.recovery)
        }
    }

    func saveSnapshot(_ habits: [Habit], revision: Int) -> SaveResult {
        do {
            guard revision >= latestPersistedRevision else {
                return SaveResult(habits: try fetchVisibleHabits(), errorDescription: nil, revision: latestPersistedRevision)
            }

            latestPersistedRevision = revision
            try replaceCache(with: habits, protectsLocalEdits: true)
            return SaveResult(habits: try fetchVisibleHabits(), errorDescription: nil, revision: revision)
        } catch {
            return SaveResult(habits: habits, errorDescription: error.localizedDescription, revision: revision)
        }
    }

    func refreshFromRemote() async -> RefreshResult {
        do {
            guard let remoteHabits = try await remoteDataSource.fetchHabits() else {
                return RefreshResult(habits: try fetchVisibleHabits(), didChange: false, errorDescription: nil)
            }

            let didChange = try mergeRemoteHabits(remoteHabits)
            return RefreshResult(habits: try fetchVisibleHabits(), didChange: didChange, errorDescription: nil)
        } catch {
            return RefreshResult(
                habits: (try? fetchVisibleHabits()) ?? [],
                didChange: false,
                errorDescription: error.localizedDescription
            )
        }
    }

    private func fetchVisibleHabits() throws -> [Habit] {
        try fetchAllRecords()
            .filter { $0.deletedAt == nil }
            .map(\.habitValue)
    }

    private func fetchAllRecords() throws -> [HabitRecord] {
        try modelContext.fetch(FetchDescriptor<HabitRecord>())
    }

    private func fetchRecordCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<HabitRecord>())
    }

    private func replaceCache(with habits: [Habit], protectsLocalEdits: Bool) throws {
        let now = dateProvider()
        let incomingByID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        let existingRecords = try fetchAllRecords()
        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })

        for habit in habits {
            if let record = existingByID[habit.id] {
                apply(habit, to: record, updatedAt: now, protectsLocalEdits: protectsLocalEdits)
            } else {
                modelContext.insert(
                    HabitRecord(
                        id: habit.id,
                        name: habit.name,
                        note: habit.note,
                        colorName: habit.colorName,
                        systemIcon: habit.systemIcon,
                        completionsData: try HabitCompletionsCoder.encode(habit.completions),
                        isPaused: habit.isPaused,
                        createdAt: habit.createdAt,
                        updatedAt: now,
                        deletedAt: nil,
                        needsLocalProtection: protectsLocalEdits
                    )
                )
            }
        }

        for record in existingRecords where incomingByID.keys.contains(record.id) == false {
            record.deletedAt = now
            record.updatedAt = now
            record.needsLocalProtection = protectsLocalEdits
        }

        try modelContext.save()
    }

    private func mergeRemoteHabits(_ remoteHabits: [RemoteHabit]) throws -> Bool {
        let remoteByID = Dictionary(uniqueKeysWithValues: remoteHabits.map { ($0.id, $0) })
        let existingRecords = try fetchAllRecords()
        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        var didChange = false

        for remoteHabit in remoteHabits {
            if let record = existingByID[remoteHabit.id] {
                if record.needsLocalProtection && record.updatedAt >= remoteHabit.updatedAt {
                    continue
                }

                didChange = apply(remoteHabit, to: record) || didChange
            } else {
                modelContext.insert(
                    HabitRecord(
                        id: remoteHabit.id,
                        name: remoteHabit.name,
                        note: remoteHabit.note,
                        colorName: remoteHabit.colorName,
                        systemIcon: remoteHabit.systemIcon,
                        completionsData: try HabitCompletionsCoder.encode(remoteHabit.completions),
                        isPaused: remoteHabit.isPaused,
                        createdAt: remoteHabit.createdAt,
                        updatedAt: remoteHabit.updatedAt
                    )
                )
                didChange = true
            }
        }

        for record in existingRecords where remoteByID[record.id] == nil {
            guard record.deletedAt == nil, record.needsLocalProtection == false else {
                continue
            }

            let now = dateProvider()
            record.deletedAt = now
            record.updatedAt = now
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }

        return didChange
    }

    private func apply(_ habit: Habit, to record: HabitRecord, updatedAt: Date, protectsLocalEdits: Bool) {
        record.name = habit.name
        record.note = habit.note
        record.colorName = habit.colorName
        record.systemIcon = habit.systemIcon
        record.completionsData = (try? HabitCompletionsCoder.encode(habit.completions)) ?? record.completionsData
        record.isPaused = habit.isPaused
        record.createdAt = habit.createdAt
        record.updatedAt = updatedAt
        record.deletedAt = nil
        record.needsLocalProtection = protectsLocalEdits
    }

    private func apply(_ remoteHabit: RemoteHabit, to record: HabitRecord) -> Bool {
        let decodedCompletions = (try? HabitCompletionsCoder.decode(record.completionsData)) ?? [:]
        let changed = record.name != remoteHabit.name ||
            record.note != remoteHabit.note ||
            record.colorName != remoteHabit.colorName ||
            record.systemIcon != remoteHabit.systemIcon ||
            decodedCompletions != remoteHabit.completions ||
            record.isPaused != remoteHabit.isPaused ||
            record.createdAt != remoteHabit.createdAt ||
            record.deletedAt != nil

        guard changed else {
            record.updatedAt = max(record.updatedAt, remoteHabit.updatedAt)
            return false
        }

        record.name = remoteHabit.name
        record.note = remoteHabit.note
        record.colorName = remoteHabit.colorName
        record.systemIcon = remoteHabit.systemIcon
        record.completionsData = (try? HabitCompletionsCoder.encode(remoteHabit.completions)) ?? record.completionsData
        record.isPaused = remoteHabit.isPaused
        record.createdAt = remoteHabit.createdAt
        record.updatedAt = remoteHabit.updatedAt
        record.deletedAt = nil
        record.needsLocalProtection = false
        return true
    }
}

private extension HabitRecord {
    var habitValue: Habit {
        let completions = (try? HabitCompletionsCoder.decode(completionsData)) ?? [:]
        return Habit(
            id: id,
            name: name,
            note: note,
            colorName: colorName,
            systemIcon: systemIcon,
            completions: completions,
            isPaused: isPaused,
            createdAt: createdAt
        )
    }
}

private enum HabitCompletionsCoder {
    nonisolated static func decode(_ data: Data) throws -> [String: Bool] {
        try JSONDecoder().decode([String: Bool].self, from: data)
    }

    nonisolated static func encode(_ completions: [String: Bool]) throws -> Data {
        try JSONEncoder().encode(completions)
    }
}
