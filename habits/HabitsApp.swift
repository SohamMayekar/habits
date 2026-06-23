import SwiftUI

enum AppTab: Hashable {
    case today
    case reflect
    case settings
}

@main
struct HabitsApp: App {

    @Environment(\.scenePhase) private var scenePhase

    @State private var store: HabitStore
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasSeededMockHabits") private var hasSeededMockHabits = false

    @State private var selectedTab: AppTab = .today
    @State private var showSplash = true

    init() {
        let repository = HabitRepository.makeDefault()
        _store = State(initialValue: HabitStore(repository: repository))
        HapticManager.shared.prepare()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView(selection: $selectedTab) {
                    Tab("Today", systemImage: "calendar", value: AppTab.today) {
                        TodayView()
                    }
                    Tab("Reflect", systemImage: "clock.arrow.circlepath", value: AppTab.reflect) {
                        HistoryView()
                    }
                    Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                        SettingsView()
                    }
                }
                .opacity(showSplash || !hasSeenOnboarding ? 0 : 1)

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                } else if !hasSeenOnboarding {
                    OnboardingView {
                        withAnimation(.easeOut(duration: 0.25)) {
                            hasSeenOnboarding = true
                        }
                    }
                    .transition(.opacity)
                }
            }
            .environment(store)
            .preferredColorScheme(appearanceMode.colorScheme)
            .task {
                await dismissSplashWhenReady()
            }
        }
    }

    private func dismissSplashWhenReady() async {
        async let minimumDisplay: Void = {
            try? await Task.sleep(for: .seconds(0.6))
        }()

        await store.awaitLoaded()
        seedMockHabitsIfNeeded()
        _ = await minimumDisplay

        withAnimation(.easeOut(duration: 0.25)) {
            showSplash = false
        }
    }

    private func seedMockHabitsIfNeeded() {
        guard hasSeededMockHabits == false, store.habits.isEmpty else { return }
        store.seedIfEmpty(with: Self.mockHabits())
        hasSeededMockHabits = true
    }

    private static func mockHabits(now: Date = Date()) -> [Habit] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        func date(dayOffset: Int) -> Date {
            calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        }

        func completions(for offsets: [Int]) -> [String: Bool] {
            Dictionary(uniqueKeysWithValues: offsets.map { offset in
                (PersistenceManager.dateKey(for: date(dayOffset: offset)), true)
            })
        }

        return [
            Habit(
                name: "Morning Walk",
                note: "A short walk to start the day fresh.",
                colorName: "green",
                systemIcon: "figure.walk",
                completions: completions(for: [-7, -6, -4, -3, -1, 0]),
                createdAt: date(dayOffset: -7)
            ),
            Habit(
                name: "Read 10 Pages",
                note: "Wind down with a little reading.",
                colorName: "blue",
                systemIcon: "book",
                completions: completions(for: [-7, -5, -4, -2, -1]),
                createdAt: date(dayOffset: -7)
            ),
            Habit(
                name: "Drink Water",
                note: "Stay hydrated through the day.",
                colorName: "teal",
                systemIcon: "drop",
                completions: completions(for: [-7, -6, -5, -4, -3, -2, -1, 0]),
                createdAt: date(dayOffset: -7)
            )
        ]
    }
}

// MARK: - App Lock Overlay

private struct AppLockOverlay: View {
    let controller: ViewProtectionController

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.todayBackgroundTop, .todayBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: AppSpacing.content) {
                Image(systemName: controller.allowsBypass ? "exclamationmark.shield.fill" : "lock.shield.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.primary)

                VStack(spacing: AppSpacing.compact) {
                    Text(controller.allowsBypass ? "App Lock Unavailable" : "Unlock Habits")
                        .font(AppType.pageTitle)

                    Text(descriptionText)
                        .font(AppType.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let failureMessage = controller.failureMessage {
                    Text(failureMessage)
                        .font(AppType.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    if controller.allowsBypass {
                        controller.unlockWithoutAuthentication()
                    } else {
                        controller.requestAuthenticationIfNeeded()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if controller.isAuthenticating {
                            ProgressView().controlSize(.small)
                        }
                        Text(controller.primaryActionTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(controller.isAuthenticating)
            }
            .frame(maxWidth: 360)
            .appCardStyle()
            .padding(.horizontal, AppSpacing.screenHorizontal)
        }
    }

    private var descriptionText: String {
        switch controller.availability {
        case .biometrics(let biometry):
            return "Use \(biometry.rawValue) to reopen Habits after it has been in the background."
        case .unavailable:
            return "Face ID or Touch ID isn't available right now. You can continue without biometric lock."
        }
    }
}

// MARK: - Onboarding
// iOS 26 native style: app's own gradient, staged reveal, native button styles.
// No black background. No TimelineView animation drain. No glass in the content layer.

private struct OnboardingView: View {

    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var iconVisible   = false
    @State private var titleVisible  = false
    @State private var listVisible   = false
    @State private var buttonVisible = false

    var body: some View {
        ZStack {
            // Same gradient as the rest of the app — consistent, not jarring.
            LinearGradient(
                colors: [.todayBackgroundTop, .todayBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .center, spacing: 0) {
                Spacer().frame(height: 56)

                iconSection
                    .opacity(iconVisible ? 1 : 0)
                    .scaleEffect(iconVisible ? 1 : 0.88)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.25),
                        value: iconVisible
                    )

                Spacer().frame(height: 28)

                VStack(spacing: 6) {
                    Text("Habits.")
                        .font(.system(.largeTitle, design: .default, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Small steps, every day.")
                        .font(AppType.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 10)
                .animation(
                    reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.1),
                    value: titleVisible
                )
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 48)

                // Plain rows on the gradient — no glass card.
                // HIG: don't use Liquid Glass in the content layer.
                featureList
                    .opacity(listVisible ? 1 : 0)
                    .offset(y: listVisible ? 0 : 12)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.1),
                        value: listVisible
                    )

                Spacer()
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)

            VStack {
                Spacer()
                ctaButton
                    .opacity(buttonVisible ? 1 : 0)
                    .offset(y: buttonVisible ? 0 : 8)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.38, bounce: 0.1),
                        value: buttonVisible
                    )
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.screenBottom + 8)
            }
            .ignoresSafeArea(.keyboard)
        }
        .task {
            // Staged cascade — each element leads the eye downward.
            if reduceMotion {
                iconVisible = true; titleVisible = true
                listVisible = true; buttonVisible = true
                return
            }
            iconVisible = true
            try? await Task.sleep(for: .milliseconds(160))
            titleVisible = true
            try? await Task.sleep(for: .milliseconds(130))
            listVisible = true
            try? await Task.sleep(for: .milliseconds(170))
            buttonVisible = true
        }
    }

    // MARK: - Icon

    private var iconSection: some View {
        ZStack {
            // Soft static halo — no TimelineView, no per-frame redraws.
            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 148, height: 148)
                .blur(radius: 26)

            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 24) {
            featureRow(
                systemImage: "checkmark.circle.fill",
                title: "One tap to check in",
                description: "Mark habits done as you move through your day."
            )
            featureRow(
                systemImage: "chart.bar.fill",
                title: "See your rhythm",
                description: "A calm view of which days you showed up."
            )
            featureRow(
                systemImage: "bell.fill",
                title: "Optional reminders",
                description: "A single daily nudge, on your schedule."
            )
        }
    }

    private func featureRow(systemImage: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppType.bodyEmphasis)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(AppType.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - CTA
    // Native button styles only — no custom ButtonStyle.
    // glassProminent on iOS 26, borderedProminent as the correct pre-26 fallback.

    @ViewBuilder
    private var ctaButton: some View {
        if #available(iOS 26, *) {
            Button {
                HapticManager.shared.play(.advanceFlow)
                onFinish()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.accentColor)
            .accessibilityHint("Starts using the app.")
        } else {
            Button {
                HapticManager.shared.play(.advanceFlow)
                onFinish()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Starts using the app.")
        }
    }
}

// MARK: - Splash Screen

private struct SplashScreenView: View {

    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.todayBackgroundTop, .todayBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 180, height: 180)
                        .blur(radius: 40)
                        .scaleEffect(phase >= 1 ? 1.0 : 0.4)
                        .opacity(phase >= 1 ? 1.0 : 0.0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: phase)

                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                        .shadow(color: .black.opacity(0.10), radius: 20, y: 10)
                        .scaleEffect(phase >= 1 ? 1.0 : 0.6)
                        .opacity(phase >= 1 ? 1.0 : 0.0)
                        .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.25), value: phase)
                }

                Spacer().frame(height: 32)

                // App name uses a text style so Dynamic Type works correctly
                Text("Habits")
                    .font(AppType.pageTitle)
                    .foregroundStyle(.primary)
                    .opacity(phase >= 2 ? 1.0 : 0.0)
                    .offset(y: phase >= 2 ? 0 : 10)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.05), value: phase)

                Spacer().frame(height: 8)

                Text("Small steps, every day")
                    .font(AppType.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(phase >= 2 ? 1.0 : 0.0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.15), value: phase)

                Spacer()
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Habits launch screen")
        .task {
            if reduceMotion {
                phase = 2
            } else {
                try? await Task.sleep(for: .milliseconds(100))
                phase = 1
                try? await Task.sleep(for: .milliseconds(250))
                phase = 2
            }
        }
    }
}
