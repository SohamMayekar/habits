import Foundation

struct PersistenceManager: Sendable {
    struct HabitArchive: Codable, Sendable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        var habits: [Habit]
        var savedAt: Date

        init(
            schemaVersion: Int = Self.currentSchemaVersion,
            habits: [Habit],
            savedAt: Date = .now
        ) {
            self.schemaVersion = schemaVersion
            self.habits = habits
            self.savedAt = savedAt
        }
    }

    struct LoadResult: Sendable {
        enum Recovery: Sendable, Equatable {
            case none
            case migratedLegacyFile
            case recoveredFromCorruption(backupURL: URL)
        }

        var habits: [Habit]
        var recovery: Recovery = .none
    }

    struct SaveResult: Sendable {
        let succeeded: Bool
        let errorDescription: String?
    }

    struct Environment: Sendable {
        var fileURL: @Sendable () -> URL = {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return directory.appendingPathComponent("habits.json")
        }
        var fileManager: FileManager = .default
        var dateProvider: @Sendable () -> Date = Date.init
    }

    nonisolated(unsafe) static let environment = Environment()

    // Thread-safe date key formatting (no DateFormatter, safe for concurrent use).
    // Use these instead of dateKeyFormatter from non-MainActor contexts.
    nonisolated static func dateKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    nonisolated static func date(fromDateKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    // DateFormatter is NOT thread-safe at runtime despite @unchecked Sendable.
    // Non-MainActor callers must use dateKey(for:) and date(fromDateKey:) above.
    nonisolated(unsafe) static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    nonisolated static func save(_ habits: [Habit]) -> SaveResult {
        save(habits, environment: environment)
    }

    nonisolated static func save(_ habits: [Habit], environment: Environment) -> SaveResult {
        let archive = HabitArchive(habits: habits, savedAt: environment.dateProvider())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(archive)
            let url = environment.fileURL()
            try data.write(to: url, options: .atomic)
            return SaveResult(succeeded: true, errorDescription: nil)
        } catch {
            return SaveResult(succeeded: false, errorDescription: error.localizedDescription)
        }
    }

    nonisolated static func load() async -> LoadResult {
        load(environment: environment)
    }

    nonisolated static func load(environment: Environment) -> LoadResult {
        let url = environment.fileURL()

        guard environment.fileManager.fileExists(atPath: url.path) else {
            return LoadResult(habits: [])
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let archive = try? decoder.decode(HabitArchive.self, from: data) {
                return LoadResult(habits: archive.habits)
            }

            if let legacyHabits = try? decoder.decode([Habit].self, from: data) {
                return LoadResult(habits: legacyHabits, recovery: .migratedLegacyFile)
            }

            let backupURL = corruptedBackupURL(for: url, now: environment.dateProvider())
            try environment.fileManager.moveItem(at: url, to: backupURL)
            return LoadResult(habits: [], recovery: .recoveredFromCorruption(backupURL: backupURL))
        } catch {
            return LoadResult(habits: [])
        }
    }

    private static func corruptedBackupURL(for originalURL: URL, now: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        return originalURL.deletingPathExtension().appendingPathExtension("corrupted-\(stamp).json")
    }
}
