import Foundation
import Testing
@testable import habits

@MainActor
@Suite("View Protection")
struct ViewProtectionControllerTests {
    @Test("Successful authentication unlocks the protected view")
    func successfulAuthenticationUnlocks() async {
        let controller = ViewProtectionController(
            authenticator: .init(
                currentAvailability: { .biometrics(.faceID) },
                authenticate: { _ in
                    .init(availability: .biometrics(.faceID), status: .succeeded)
                }
            )
        )

        controller.lock()
        await controller.authenticateIfNeeded()

        #expect(controller.isLocked == false)
        #expect(controller.failureMessage == nil)
    }

    @Test("Failed authentication keeps the protected view locked")
    func failedAuthenticationKeepsLock() async {
        let controller = ViewProtectionController(
            authenticator: .init(
                currentAvailability: { .biometrics(.touchID) },
                authenticate: { _ in
                    .init(availability: .biometrics(.touchID), status: .failed("Authentication failed. Try again."))
                }
            )
        )

        controller.lock()
        await controller.authenticateIfNeeded()

        #expect(controller.isLocked)
        #expect(controller.failureMessage == "Authentication failed. Try again.")
        #expect(controller.allowsBypass == false)
    }

    @Test("Unavailable biometrics allow an explicit bypass")
    func unavailableAuthenticationCanBeBypassed() async {
        let controller = ViewProtectionController(
            authenticator: .init(
                currentAvailability: { .unavailable("Unavailable") },
                authenticate: { _ in
                    .init(
                        availability: .unavailable("Unavailable"),
                        status: .unavailable("Unavailable")
                    )
                }
            )
        )

        controller.lock()
        await controller.authenticateIfNeeded()

        #expect(controller.isLocked)
        #expect(controller.allowsBypass)

        controller.unlockWithoutAuthentication()

        #expect(controller.isLocked == false)
        #expect(controller.failureMessage == nil)
    }

    @Test("Delayed app lock waits until the selected timeout has elapsed")
    func delayedAppLockRespectsTimeout() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let controller = ViewProtectionController(
            authenticator: .init(
                currentAvailability: { .biometrics(.faceID) },
                authenticate: { _ in
                    .init(availability: .biometrics(.faceID), status: .succeeded)
                }
            ),
            now: { clock.now }
        )

        controller.noteAppDidEnterBackground()
        clock.advance(by: 59)
        controller.updateLockStateOnForeground(isEnabled: true, timeout: .afterOneMinute)

        #expect(controller.isLocked == false)
    }

    @Test("App lock activates once the selected timeout is reached")
    func delayedAppLockTriggersAfterTimeout() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let controller = ViewProtectionController(
            authenticator: .init(
                currentAvailability: { .biometrics(.touchID) },
                authenticate: { _ in
                    .init(availability: .biometrics(.touchID), status: .succeeded)
                }
            ),
            now: { clock.now }
        )

        controller.noteAppDidEnterBackground()
        clock.advance(by: 15 * 60)
        controller.updateLockStateOnForeground(isEnabled: true, timeout: .afterFifteenMinutes)

        #expect(controller.isLocked)
    }

    @Test("Persisted background time can trigger lock on a fresh launch")
    func persistedBackgroundTimeTriggersLock() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 10_000))
        let controller = ViewProtectionController(
            authenticator: .init(
                currentAvailability: { .biometrics(.faceID) },
                authenticate: { _ in
                    .init(availability: .biometrics(.faceID), status: .succeeded)
                }
            ),
            now: { clock.now }
        )

        let persistedBackgroundDate = Date(timeIntervalSince1970: 9_000)
        controller.updateLockStateOnForeground(
            isEnabled: true,
            timeout: .afterFifteenMinutes,
            lastBackgroundDate: persistedBackgroundDate
        )

        #expect(controller.isLocked)
    }

    @Test(arguments: [
        (AppLockTimeout.immediately, 0.0, true),
        (AppLockTimeout.afterOneMinute, 59.0, false),
        (AppLockTimeout.afterOneMinute, 60.0, true),
        (AppLockTimeout.afterFifteenMinutes, 899.0, false),
        (AppLockTimeout.afterFifteenMinutes, 900.0, true),
        (AppLockTimeout.afterOneHour, 3599.0, false),
        (AppLockTimeout.afterOneHour, 3600.0, true)
    ])
    func appLockTimeoutThresholds(timeout: AppLockTimeout, elapsedTime: TimeInterval, expected: Bool) {
        #expect(timeout.shouldLock(elapsedTime: elapsedTime) == expected)
    }
}

private final class TestClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
