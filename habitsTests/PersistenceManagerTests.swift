import Foundation
import Testing
@testable import habits

@MainActor
@Suite("Persistence Manager", .serialized)
struct PersistenceManagerTests {
    @Test("Save and load round trip uses the archive format")
    func roundTrip() throws {
        let fileManager = FileManager.default
        let directory = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("habits.json")
        let environment = PersistenceManager.Environment(
            fileURL: { fileURL },
            fileManager: fileManager,
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let habits = [Habit(name: "Read", note: "Ten minutes", colorName: "blue", systemIcon: "book")]
        let saveResult = PersistenceManager.save(habits, environment: environment)
        #expect(saveResult.succeeded)

        let loadResult = PersistenceManager.load(environment: environment)
        #expect(loadResult.habits == habits)
        #expect(loadResult.recovery == .none)
    }

    @Test("Legacy habit arrays migrate forward")
    func legacyMigration() throws {
        let fileManager = FileManager.default
        let directory = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("habits.json")
        let habits = [Habit(name: "Walk", colorName: "green", systemIcon: "figure.walk")]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(habits).write(to: fileURL)

        let result = PersistenceManager.load(environment: .init(fileURL: { fileURL }, fileManager: fileManager))
        #expect(result.habits == habits)
        #expect(result.recovery == .migratedLegacyFile)
    }

    @Test("Corrupt files are backed up and replaced with empty data")
    func corruptionRecovery() throws {
        let fileManager = FileManager.default
        let directory = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("habits.json")
        try Data("not-json".utf8).write(to: fileURL)

        let result = PersistenceManager.load(environment: .init(
            fileURL: { fileURL },
            fileManager: fileManager,
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        ))

        #expect(result.habits.isEmpty)
        switch result.recovery {
        case .recoveredFromCorruption(let backupURL):
            #expect(fileManager.fileExists(atPath: backupURL.path))
            #expect(fileManager.fileExists(atPath: fileURL.path) == false)
        default:
            Issue.record("Expected corruption recovery backup.")
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
