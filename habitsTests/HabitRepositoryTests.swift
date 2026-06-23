import Foundation
import SwiftData
import Testing
@testable import habits

@MainActor
@Suite("Habit Repository", .serialized)
struct HabitRepositoryTests {
    @Test("Remote refresh merges new records without overwriting newer local edits")
    func refreshMergePrefersProtectedLocalEdits() async {
        let container = try! ModelContainer(
            for: HabitRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let remoteHabitID = UUID()
        let preservedHabitID = UUID()
        let remoteDate = Date(timeIntervalSince1970: 1_734_739_200)
        let localDate = remoteDate.addingTimeInterval(120)
        let remoteSource = StubRemoteDataSource(result: [
            RemoteHabit(
                id: remoteHabitID,
                name: "Meditate",
                note: "Five minutes",
                colorName: "mint",
                systemIcon: "brain.head.profile",
                completions: [:],
                isPaused: false,
                createdAt: remoteDate,
                updatedAt: remoteDate
            ),
            RemoteHabit(
                id: preservedHabitID,
                name: "Remote Title",
                note: "",
                colorName: "blue",
                systemIcon: "book",
                completions: [:],
                isPaused: false,
                createdAt: remoteDate,
                updatedAt: remoteDate
            )
        ])
        let repository = HabitRepository(
            container: container,
            remoteDataSource: remoteSource,
            dateProvider: { localDate }
        )

        _ = await repository.saveSnapshot([
            Habit(
                id: preservedHabitID,
                name: "Local Title",
                note: "Keep this",
                colorName: "green",
                systemIcon: "leaf",
                createdAt: remoteDate
            )
        ], revision: 1)

        let result = await repository.refreshFromRemote()

        #expect(result.didChange)
        #expect(result.habits.count == 2)
        #expect(result.habits.contains(where: { $0.id == remoteHabitID && $0.name == "Meditate" }))
        #expect(result.habits.contains(where: { $0.id == preservedHabitID && $0.name == "Local Title" }))
    }
}

private struct StubRemoteDataSource: HabitRemoteDataSource {
    let result: [RemoteHabit]?

    func fetchHabits() async throws -> [RemoteHabit]? {
        result
    }
}
