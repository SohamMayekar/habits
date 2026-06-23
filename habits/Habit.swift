import Foundation
import SwiftUI

// Habit model

// Stores data for one habit
struct Habit: Identifiable, Codable, Sendable, Hashable {

    let id: UUID
    var name: String
    var note: String
    var colorName: String
    var systemIcon: String
    var completions: [String: Bool]
    var isPaused: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        colorName: String = "green",
        systemIcon: String = "circle",
        completions: [String: Bool] = [:],
        isPaused: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.colorName = colorName
        self.systemIcon = systemIcon
        self.completions = completions
        self.isPaused = isPaused
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case note
        case colorName
        case systemIcon
        case completions
        case isPaused
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? "green"
        systemIcon = try container.decodeIfPresent(String.self, forKey: .systemIcon) ?? "circle"
        completions = try container.decodeIfPresent([String: Bool].self, forKey: .completions) ?? [:]
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// Habit colors and icons

extension Habit {
    typealias ColorOption = (displayName: String, key: String)
    static let maxNameLength = 40
    static let maxNoteLength = 120

    // Color list used in the app
    static let colorOptions: [ColorOption] = [
        ("Green",  "green"),
        ("Blue",   "blue"),
        ("Purple", "purple"),
        ("Orange", "orange"),
        ("Pink",   "pink"),
        ("Teal",   "teal"),
        ("Red",    "red"),
        ("Yellow", "yellow"),
        ("Mint",   "mint"),
        ("Indigo", "indigo"),
        ("Brown",  "brown"),
        ("Gray",   "gray")
    ]

    // Icon list used in the app
    static let iconOptions: [String] = [
        "circle", "star", "heart", "leaf", "drop",
        "flame", "bolt", "moon", "sun.max",
        "book", "pencil", "display", "headphones",
        "figure.walk", "bicycle", "dumbbell", "cup.and.saucer",
        "fork.knife", "bed.double", "briefcase", "dollarsign.circle",
        "cross.case", "pill", "brain.head.profile"
    ]

    // Convert saved color name to SwiftUI color
    static func color(for name: String) -> Color {
        switch name {
        case "green":   return .green
        case "blue":    return .blue
        case "purple":  return Color(red: 0.6, green: 0.4, blue: 0.9)
        case "orange":  return .orange
        case "pink":    return .pink
        case "teal":    return .teal
        case "red":     return .red
        case "yellow":  return .yellow
        case "mint":    return .mint
        case "indigo":  return .indigo
        case "brown":   return .brown
        case "gray":    return .gray
        default:        return .green
        }
    }

    // Returns the color of this habit
    var tintColor: Color {
        Self.color(for: colorName)
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
