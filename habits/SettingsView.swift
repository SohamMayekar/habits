import StoreKit
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {

    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("gentleReminderEnabled") private var gentleReminderEnabled = false
    @AppStorage("gentleReminderTime") private var gentleReminderTime = Self.defaultReminderTime.timeIntervalSinceReferenceDate
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled = true

    @Environment(HabitStore.self) private var store
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL)       private var openURL

    @State private var reminderStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingResetConfirmation = false
    @State private var showingReminderSettingsPrompt = false
    @State private var activePermissionDestination: PermissionDestination?
    @State private var isRequestingNotificationPermission = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView

                Form {
                    // Appearance & Experience
                    Section {
                        Picker(selection: $appearanceMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        } label: {
                            settingRow(icon: "moon.fill", color: .indigo, title: "Appearance")
                        }
                        .pickerStyle(.menu)

                        Toggle(isOn: $hapticFeedbackEnabled) {
                            settingRow(icon: "waveform", color: .purple, title: "Haptic Feedback")
                        }
                        .accessibilityHint("Toggles vibration feedback for taps and actions.")
                    } header: {
                        Text("Experience")
                    }

                    // Reminders
                    Section {
                        Toggle(isOn: reminderToggleBinding) {
                            settingRow(icon: "bell.badge.fill", color: .teal, title: "Daily Reminder")
                        }
                        .accessibilityHint("Turns the daily reminder on or off.")

                        if gentleReminderEnabled {
                            DatePicker(
                                "Time",
                                selection: reminderDateBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .accessibilityHint("Choose when the daily reminder arrives.")
                        }

                        if reminderStatus == .denied {
                            Button {
                                showingReminderSettingsPrompt = true
                            } label: {
                                settingRow(
                                    icon: "gearshape.fill",
                                    color: .orange,
                                    title: "Open Notification Settings",
                                    isButton: true
                                )
                            }
                            .accessibilityHint("Opens iPhone Settings to enable notifications.")
                        }
                    } header: {
                        Text("Reminder")
                    } footer: {
                        Text(ReminderManager.footerText(for: reminderStatus))
                    }

                    // Your Data
                    Section {
                        LabeledContent("Total Habits") {
                            Text("\(store.habits.count)")
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("Active") {
                            Text("\(store.activeHabits.count)")
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("Paused") {
                            Text("\(store.pausedHabits.count)")
                                .foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) {
                            showingResetConfirmation = true
                        } label: {
                            settingRow(icon: "trash.fill", color: .red, title: "Reset All Data", isButton: true)
                        }
                        .accessibilityHint("Deletes all habits and turns off reminders.")
                    } header: {
                        Text("Your Data")
                    }

                    // Support & Feedback
                    Section {
                        Button {
                            requestReview()
                        } label: {
                            settingRow(icon: "star.fill", color: .yellow, title: "Rate Habits", isButton: true)
                        }
                        .accessibilityHint("Opens the App Store review prompt.")

                        if let supportURL = AppSupport.supportEmailURL {
                            Link(destination: supportURL) {
                                settingRow(icon: "envelope.fill", color: .blue, title: "Contact Support", isButton: true)
                            }
                            .accessibilityHint("Opens Mail to contact support.")
                        }

                        if let privacyURL = AppSupport.privacyPolicyURL {
                            Link(destination: privacyURL) {
                                settingRow(icon: "lock.shield.fill", color: .mint, title: "Privacy Policy", isButton: true)
                            }
                            .accessibilityHint("Opens the privacy policy in Safari.")
                        }

                        ShareLink(
                            item: URL(string: "https://apps.apple.com/app/habits")!,
                            subject: Text("Habits — Small steps, every day"),
                            message: Text("I've been using Habits to build calm, daily routines. Give it a try.")
                        ) {
                            settingRow(icon: "square.and.arrow.up.fill", color: .cyan, title: "Share Habits", isButton: true)
                        }
                        .accessibilityHint("Shares a link to the app.")
                    } header: {
                        Text("Support")
                    }

                    // About
                    Section {
                        LabeledContent("Version", value: AppSupport.versionString)
                        
                        LabeledContent("Developed By", value: "Soham Mayekar")
                    } header: {
                        Text("About")
                    } footer: {
                        Text("No accounts. No cloud. Your data stays on this device.")
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .contentMargins(.bottom, AppSpacing.screenBottom, for: .scrollContent)
                .appScrollChrome()
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.large)
            .preferredColorScheme(appearanceMode.colorScheme)
            .task {
                reminderStatus = await ReminderManager.authorizationStatus()
            }
            .alert(
                "Clear everything?",
                isPresented: $showingResetConfirmation
            ) {
                Button("Clear everything", role: .destructive) {
                    store.deleteAll()
                    ReminderManager.removeReminder()
                    gentleReminderEnabled = false
                    HapticManager.shared.play(.destructiveDelete)
                }
                Button("Never mind", role: .cancel) { }
            } message: {
                Text("This removes all habits and turns off reminders. There's no going back.")
            }
            .alert(
                "Open Settings?",
                isPresented: $showingReminderSettingsPrompt
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Notifications are currently turned off for Habits.")
            }
            .sheet(item: $activePermissionDestination) { destination in
                switch destination {
                case .notifications:
                    NotificationPrePermissionView(
                        status: reminderStatus,
                        isRequesting: isRequestingNotificationPermission,
                        onContinue: {
                            Task { await requestNotificationPermissionFromPrimer() }
                        },
                        onOpenSettings: openAppSettings
                    )
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        LinearGradient(
            colors: [.todayBackgroundTop, .todayBackgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Notification Status

    private var notificationStatusSummary: String {
        switch reminderStatus {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied:                                return "Denied"
        case .notDetermined:                         return "Not Set"
        @unknown default:                            return "Unknown"
        }
    }

    // MARK: - Default Time

    private static var defaultReminderTime: Date {
        Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Bindings

    private var reminderToggleBinding: Binding<Bool> {
        Binding {
            gentleReminderEnabled
        } set: { newValue in
            guard newValue else {
                gentleReminderEnabled = false
                Task {
                    ReminderManager.removeReminder()
                    reminderStatus = await ReminderManager.authorizationStatus()
                    await MainActor.run { HapticManager.shared.play(.pauseStateChanged) }
                }
                return
            }

            if reminderStatus == .notDetermined {
                activePermissionDestination = .notifications
                return
            }

            gentleReminderEnabled = newValue
            Task {
                let granted = await ReminderManager.scheduleDailyReminder(at: reminderDate)
                reminderStatus = await ReminderManager.authorizationStatus()
                if !granted {
                    gentleReminderEnabled = false
                    showingReminderSettingsPrompt = reminderStatus == .denied
                    await MainActor.run { HapticManager.shared.play(.reminderPermissionWarning) }
                } else {
                    await MainActor.run { HapticManager.shared.play(.reminderEnabled) }
                }
            }
        }
    }

    private var reminderDateBinding: Binding<Date> {
        Binding {
            reminderDate
        } set: { newValue in
            gentleReminderTime = newValue.timeIntervalSinceReferenceDate
            guard gentleReminderEnabled else { return }
            Task {
                _ = await ReminderManager.scheduleDailyReminder(at: newValue)
                reminderStatus = await ReminderManager.authorizationStatus()
            }
        }
    }

    private var reminderDate: Date {
        Date(timeIntervalSinceReferenceDate: gentleReminderTime)
    }

    // MARK: - Permission Flow

    private func requestNotificationPermissionFromPrimer() async {
        guard !isRequestingNotificationPermission else { return }

        isRequestingNotificationPermission = true
        let status = await ReminderManager.requestAuthorizationAfterPrimer()
        reminderStatus = status
        isRequestingNotificationPermission = false

        guard ReminderManager.isAuthorized(status) else {
            gentleReminderEnabled = false
            if status == .denied { HapticManager.shared.play(.reminderPermissionWarning) }
            return
        }

        let scheduled = await ReminderManager.scheduleDailyReminder(at: reminderDate)
        gentleReminderEnabled = scheduled

        if scheduled {
            HapticManager.shared.play(.reminderEnabled)
            activePermissionDestination = nil
        } else {
            HapticManager.shared.play(.reminderPermissionWarning)
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func settingRow(icon: String, color: Color, title: String, isButton: Bool = false) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(AppType.bodyEmphasis)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.settingIcon, style: .continuous)
                        .fill(color)
                )
                .accessibilityHidden(true)

            Text(title)
                .font(AppType.body)
                .foregroundStyle(isButton ? color : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
