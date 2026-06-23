import Foundation
import UserNotifications

@MainActor
enum ReminderManager {
    static let reminderIdentifier = "daily-gentle-reminder"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    static func requestAuthorizationAfterPrimer() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral, .denied:
            return settings.authorizationStatus
        case .notDetermined:
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch { }
            let updatedSettings = await center.notificationSettings()
            return updatedSettings.authorizationStatus
        @unknown default:
            return settings.authorizationStatus
        }
    }

    nonisolated static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    static func scheduleDailyReminder(at date: Date) async -> Bool {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return false }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "A quiet check-in")
        content.body = String(localized: "If today allows it, your habits are here.")
        content.sound = .default
        content.threadIdentifier = reminderIdentifier

        let components = reminderComponents(for: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    static func removeReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [reminderIdentifier])
    }

    nonisolated static func reminderComponents(for date: Date, calendar: Calendar = .current) -> DateComponents {
        calendar.dateComponents([.hour, .minute], from: date)
    }

    nonisolated static func footerText(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return String(localized: "Notifications are off for Habits. You can turn them back on in Settings if a gentle reminder would help.")
        case .authorized, .provisional, .ephemeral:
            return String(localized: "One daily reminder, delivered quietly at the time you choose.")
        case .notDetermined:
            return String(localized: "Optional and light. Habits asks once, then leaves the choice with you.")
        @unknown default:
            return String(localized: "Optional and light. Habits keeps reminders simple.")
        }
    }
}
