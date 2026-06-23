import SwiftUI
import UserNotifications

enum PermissionDestination: String, Identifiable {
    case notifications

    var id: String { rawValue }
}

struct NotificationPrePermissionView: View {
    let status: UNAuthorizationStatus
    let isRequesting: Bool
    let onContinue: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Daily reminders", systemImage: "bell.badge")
                    Label("You choose the reminder time", systemImage: "clock")
                    Label("You can change this later in Settings", systemImage: "gearshape")
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Habits sends at most one daily reminder. Notifications remain optional.")
                }

                Section {
                    LabeledContent("Status", value: notificationStateTitle)

                    Text(notificationStateMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Button(primaryActionTitle, action: primaryAction)
                        .disabled(isRequesting)

                    if let secondaryActionTitle {
                        Button(secondaryActionTitle, role: .cancel, action: secondaryAction)
                    }
                } footer: {
                    if isRequesting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for the system permission prompt.")
                        }
                    }
                }
            }
            .navigationTitle("Notification Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var notificationStateTitle: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Turned Off"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var notificationStateMessage: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Notifications are already enabled for Habits."
        case .denied:
            return "To enable reminders again, allow notifications for Habits in the Settings app."
        case .notDetermined:
            return "Continue to show the system notification permission prompt."
        @unknown default:
            return "Review notification access for Habits."
        }
    }

    private var primaryActionTitle: String {
        switch status {
        case .notDetermined:
            return "Continue"
        case .denied:
            return "Open Settings"
        case .authorized, .provisional, .ephemeral:
            return "Done"
        @unknown default:
            return "Done"
        }
    }

    private var secondaryActionTitle: String? {
        status == .notDetermined ? "Not Now" : nil
    }

    private func primaryAction() {
        switch status {
        case .notDetermined:
            onContinue()
        case .denied:
            onOpenSettings()
        case .authorized, .provisional, .ephemeral:
            dismiss()
        @unknown default:
            dismiss()
        }
    }

    private func secondaryAction() {
        dismiss()
    }
}
