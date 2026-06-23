import Foundation
import LocalAuthentication

enum AppLockTimeout: String, CaseIterable, Identifiable, Sendable {
    case immediately
    case afterOneMinute
    case afterFifteenMinutes
    case afterOneHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediately:
            return "Immediately"
        case .afterOneMinute:
            return "After 1 Minute"
        case .afterFifteenMinutes:
            return "After 15 Minutes"
        case .afterOneHour:
            return "After 1 Hour"
        }
    }

    fileprivate var seconds: TimeInterval {
        switch self {
        case .immediately:
            return 0
        case .afterOneMinute:
            return 60
        case .afterFifteenMinutes:
            return 15 * 60
        case .afterOneHour:
            return 60 * 60
        }
    }

    func shouldLock(elapsedTime: TimeInterval) -> Bool {
        elapsedTime >= seconds
    }
}

enum DeviceBiometry: String, Sendable, Equatable {
    case faceID = "Face ID"
    case touchID = "Touch ID"
    case opticID = "Optic ID"
    case biometrics = "Biometrics"
}

enum DeviceAuthenticationAvailability: Sendable, Equatable {
    case biometrics(DeviceBiometry)
    case unavailable(String)

    var actionTitle: String {
        switch self {
        case .biometrics(let biometry):
            return "Unlock with \(biometry.rawValue)"
        case .unavailable:
            return "Continue Without Lock"
        }
    }
}

enum DeviceAuthenticationStatus: Sendable, Equatable {
    case succeeded
    case cancelled
    case failed(String)
    case unavailable(String)
}

struct DeviceAuthenticationAttempt: Sendable, Equatable {
    let availability: DeviceAuthenticationAvailability
    let status: DeviceAuthenticationStatus
}

struct DeviceAuthenticator: Sendable {
    var currentAvailability: @MainActor @Sendable () -> DeviceAuthenticationAvailability
    var authenticate: @MainActor @Sendable (_ reason: String) async -> DeviceAuthenticationAttempt

    static let live = DeviceAuthenticator(
        currentAvailability: {
            let context = LAContext()
            return availability(for: context)
        },
        authenticate: { reason in
            let context = LAContext()
            let availability = availability(for: context)

            switch availability {
            case .biometrics:
                context.localizedFallbackTitle = ""
            case .unavailable(let message):
                return DeviceAuthenticationAttempt(
                    availability: availability,
                    status: .unavailable(message)
                )
            }

            context.localizedCancelTitle = "Not Now"

            do {
                _ = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )

                return DeviceAuthenticationAttempt(
                    availability: availability,
                    status: .succeeded
                )
            } catch let error as LAError {
                return DeviceAuthenticationAttempt(
                    availability: availability,
                    status: status(for: error)
                )
            } catch {
                return DeviceAuthenticationAttempt(
                    availability: availability,
                    status: .failed("Authentication didn’t complete. Try again.")
                )
            }
        }
    )
}

@MainActor
@Observable
final class ViewProtectionController {
    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    private(set) var allowsBypass = false
    private(set) var failureMessage: String?
    private(set) var availability: DeviceAuthenticationAvailability
    private(set) var lastBackgroundDate: Date?

    private let authenticator: DeviceAuthenticator
    private let now: @MainActor @Sendable () -> Date
    private var authenticationTask: Task<Void, Never>?

    init() {
        self.authenticator = .live
        self.now = Date.init
        self.availability = self.authenticator.currentAvailability()
    }

    init(
        authenticator: DeviceAuthenticator,
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.authenticator = authenticator
        self.now = now
        self.availability = authenticator.currentAvailability()
    }

    var primaryActionTitle: String {
        availability.actionTitle
    }

    func refreshAvailability() {
        availability = authenticator.currentAvailability()
    }

    func lock() {
        refreshAvailability()
        isLocked = true
        isAuthenticating = false
        allowsBypass = false
        failureMessage = nil
    }

    func noteAppDidEnterBackground(at date: Date? = nil) {
        lastBackgroundDate = date ?? now()
    }

    func updateLockStateOnForeground(
        isEnabled: Bool,
        timeout: AppLockTimeout,
        lastBackgroundDate overrideBackgroundDate: Date? = nil
    ) {
        guard isEnabled else {
            lastBackgroundDate = nil
            unlockWithoutAuthentication()
            return
        }

        let evaluationDate = overrideBackgroundDate ?? lastBackgroundDate

        guard let evaluationDate else {
            lock() // Cold start always locks unless disabled
            return
        }

        let elapsedTime = now().timeIntervalSince(evaluationDate)
        self.lastBackgroundDate = nil

        guard timeout.shouldLock(elapsedTime: elapsedTime) else {
            return
        }

        lock()
    }

    func authenticateIfNeeded() async {
        guard isLocked, !isAuthenticating, !allowsBypass else {
            return
        }

        isAuthenticating = true
        let attempt = await authenticator.authenticate("Unlock Habits with Face ID or Touch ID.")
        isAuthenticating = false
        availability = attempt.availability

        switch attempt.status {
        case .succeeded:
            isLocked = false
            allowsBypass = false
            failureMessage = nil
        case .cancelled:
            failureMessage = nil
        case .failed(let message):
            failureMessage = message
        case .unavailable(let message):
            allowsBypass = true
            failureMessage = message
        }
    }

    func requestAuthenticationIfNeeded() {
        // If already authenticating, let the current prompt finish.
        // Cancelling mid-authenticate leaves isAuthenticating stuck true.
        guard !isAuthenticating else { return }
        authenticationTask?.cancel()
        authenticationTask = Task {
            await authenticateIfNeeded()
        }
    }

    func unlockWithoutAuthentication() {
        isLocked = false
        isAuthenticating = false
        allowsBypass = false
        failureMessage = nil
    }
}

private func availability(for context: LAContext) -> DeviceAuthenticationAvailability {
    var error: NSError?

    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
        return .biometrics(biometry(for: context.biometryType))
    }

    return .unavailable(unavailableMessage(for: error as? LAError))
}

private func biometry(for type: LABiometryType) -> DeviceBiometry {
    switch type {
    case .faceID:
        return .faceID
    case .touchID:
        return .touchID
    case .opticID:
        return .opticID
    default:
        return .biometrics
    }
}

private func unavailableMessage(for error: LAError?) -> String {
    switch error?.code {
    case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
        return "Face ID or Touch ID isn’t available on this device right now, so Habits can’t enforce biometric app lock."
    default:
        return "Secure screen protection isn’t available on this device right now."
    }
}

private func status(for error: LAError) -> DeviceAuthenticationStatus {
    switch error.code {
    case .userCancel, .systemCancel, .appCancel:
        return .cancelled
    case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
        return .unavailable(unavailableMessage(for: error))
    case .authenticationFailed:
        return .failed("Authentication failed. Try again.")
    case .biometryLockout:
        return .failed("Biometrics are locked. Unlock your device first, then try again.")
    case .invalidContext, .notInteractive:
        return .failed("Authentication is temporarily unavailable. Try again.")
    default:
        return .failed("Authentication didn’t complete. Try again.")
    }
}
