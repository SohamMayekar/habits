import Foundation
import UIKit

enum AppSupport {
    nonisolated static let privacyPolicyURL: URL? = nil
    nonisolated static let supportEmailAddress: String? = nil
    nonisolated static let habitsFeedURL: URL? = nil

    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var supportEmailURL: URL? {
        guard let supportEmailAddress else { return nil }
        return URL(string: "mailto:\(supportEmailAddress)")
    }
}

@MainActor
final class HapticManager {
    enum Event {
        case optionChanged
        case openComposer
        case advanceFlow
        case habitCompleted
        case habitUnchecked
        case pauseStateChanged
        case destructiveDelete
        case habitSaved
        case reminderEnabled
        case validationWarning
        case reminderPermissionWarning
        case operationError
    }

    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        prepare()
    }

    func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        notification.prepare()
        selection.prepare()
    }

    func play(_ event: Event) {
        // Respect the user's haptic preference set in Settings.
        guard UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") as? Bool != false else { return }

        switch event {
        case .optionChanged:
            selection.selectionChanged()
            selection.prepare()
        case .openComposer, .advanceFlow, .habitUnchecked, .pauseStateChanged:
            lightImpact.impactOccurred()
            lightImpact.prepare()
        case .habitCompleted:
            mediumImpact.impactOccurred(intensity: 0.85)
            mediumImpact.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.065) { [weak self] in
                self?.lightImpact.impactOccurred(intensity: 0.5)
                self?.lightImpact.prepare()
            }
        case .destructiveDelete:
            heavyImpact.impactOccurred()
            heavyImpact.prepare()
        case .habitSaved, .reminderEnabled:
            notification.notificationOccurred(.success)
            notification.prepare()
        case .validationWarning, .reminderPermissionWarning:
            notification.notificationOccurred(.warning)
            notification.prepare()
        case .operationError:
            notification.notificationOccurred(.error)
            notification.prepare()
        }
    }
}
