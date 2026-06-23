import Foundation
import Testing
import UserNotifications
@testable import habits

@Suite("Reminder Manager")
struct ReminderManagerTests {
    @Test("Reminder components keep only hour and minute")
    func reminderComponents() {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 2
        components.hour = 19
        components.minute = 30
        components.second = 12
        let date = Calendar(identifier: .gregorian).date(from: components) ?? .now

        let reminder = ReminderManager.reminderComponents(for: date, calendar: Calendar(identifier: .gregorian))
        #expect(reminder.hour == 19)
        #expect(reminder.minute == 30)
        #expect(reminder.second == nil)
    }

    @Test(arguments: [
        UNAuthorizationStatus.denied,
        .authorized,
        .notDetermined
    ])
    func footerText(status: UNAuthorizationStatus) {
        let text = ReminderManager.footerText(for: status)
        #expect(text.isEmpty == false)
    }
}
