import SwiftUI
import UIKit

// MARK: - View Helpers

extension View {
    func reduceMotionAnimation<V: Equatable>(
        _ animation: Animation,
        value: V,
        reduceMotion: Bool
    ) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }

    /// Glass surface (non-interactive). Pre-iOS 26 falls back to ultraThinMaterial.
    @ViewBuilder
    func premiumSurface(cornerRadius: CGFloat = 28) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.todayStrongStroke, lineWidth: 0.5)
                }
        }
    }

    /// Glass surface with interactive press response.
    @ViewBuilder
    func premiumInteractiveSurface(cornerRadius: CGFloat = 28, tint: Color = .clear) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.todayStrongStroke, lineWidth: 0.5)
                }
        }
    }

    func appCardStyle() -> some View {
        self
            .padding(AppSpacing.cardPadding)
            .background(AppCardBackground())
    }

    func appCardStyle(compact: Bool) -> some View {
        self
            .padding(compact ? AppSpacing.cardPaddingCompact : AppSpacing.cardPadding)
            .background(AppCardBackground())
    }

    func appHighlightCardStyle() -> some View {
        self
            .padding(AppSpacing.cardPadding)
            .background(AppHighlightCardBackground())
    }

    @ViewBuilder
    func appScrollChrome() -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

// MARK: - Type Scale

enum AppType {
    // Display hierarchy
    static let screenTitle  = Font.largeTitle.bold()
    static let heroTitle    = Font.largeTitle.bold()
    static let pageTitle    = Font.title2.bold()

    // Text hierarchy — SF Pro Text
    static let sectionTitle   = Font.headline.weight(.semibold)
    static let sectionLabel   = Font.footnote.weight(.semibold)
    static let body           = Font.body
    static let bodyEmphasis   = Font.body.weight(.medium)
    static let subheadline    = Font.subheadline.weight(.medium)
    static let footnote       = Font.footnote.weight(.medium)
    static let caption        = Font.caption.weight(.medium)
    static let captionStrong  = Font.caption.weight(.semibold)

    // Numeric metrics
    static let metric      = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let metricSmall = Font.system(.title3,    design: .rounded, weight: .semibold)

    // Icons
    static let icon      = Font.body.weight(.semibold)
    static let iconSmall = Font.callout.weight(.semibold)
}

// MARK: - Spacing

enum AppSpacing {
    static let screenHorizontal: CGFloat = 20
    static let screenTop:        CGFloat = 24
    static let screenBottom:     CGFloat = 36
    static let section:          CGFloat = 20
    static let cardStack:        CGFloat = 16
    static let item:             CGFloat = 12
    static let compact:          CGFloat = 8
    static let content:          CGFloat = 18
    static let cardPadding:      CGFloat = 22
    static let cardPaddingCompact: CGFloat = 18
}

// MARK: - Corner Radii

enum AppRadius {
    static let card:        CGFloat = 28
    static let cardLarge:   CGFloat = 32
    static let control:     CGFloat = 18
    static let chip:        CGFloat = 14
    static let settingIcon: CGFloat = 8
}

// MARK: - Card Backgrounds

struct AppCardBackground: View {
    var body: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: AppRadius.card))
        } else {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .strokeBorder(Color.todayStrongStroke, lineWidth: 0.5)
                }
                .shadow(color: .todayShadow, radius: 16, y: 8)
        }
    }
}

struct AppHighlightCardBackground: View {
    var body: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: AppRadius.cardLarge, style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(Color.todayBackgroundAccent.opacity(0.15)),
                    in: .rect(cornerRadius: AppRadius.cardLarge)
                )
        } else {
            RoundedRectangle(cornerRadius: AppRadius.cardLarge, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.cardLarge, style: .continuous)
                        .strokeBorder(Color.todayStrongStroke, lineWidth: 0.6)
                }
                .shadow(color: .todayShadow, radius: 18, y: 10)
        }
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Color System

extension Color {
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // Brand background gradient
    static let todayBackgroundTop = adaptive(
        light: UIColor(red: 0.982, green: 0.972, blue: 0.956, alpha: 1),
        dark:  UIColor(red: 0.090, green: 0.100, blue: 0.120, alpha: 1)
    )
    static let todayBackgroundBottom = adaptive(
        light: UIColor(red: 0.948, green: 0.940, blue: 0.925, alpha: 1),
        dark:  UIColor(red: 0.050, green: 0.060, blue: 0.080, alpha: 1)
    )
    static let todayBackgroundAccent = adaptive(
        light: UIColor(red: 0.83, green: 0.89, blue: 0.96, alpha: 0.36),
        dark:  UIColor(red: 0.25, green: 0.35, blue: 0.48, alpha: 0.34)
    )
    static let reflectBackgroundWarm = adaptive(
        light: UIColor(red: 0.93, green: 0.77, blue: 0.57, alpha: 0.22),
        dark:  UIColor(red: 0.36, green: 0.24, blue: 0.16, alpha: 0.30)
    )
    static let reflectBackgroundCool = adaptive(
        light: UIColor(red: 0.63, green: 0.75, blue: 0.85, alpha: 0.24),
        dark:  UIColor(red: 0.20, green: 0.32, blue: 0.42, alpha: 0.32)
    )

    // Surface fills
    static let todayCardFill = adaptive(
        light: UIColor(white: 1, alpha: 0.68),
        dark:  UIColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 0.92)
    )
    static let todaySecondaryCardFill = adaptive(
        light: UIColor(white: 1, alpha: 0.66),
        dark:  UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 0.92)
    )
    static let todayControlFill = adaptive(
        light: UIColor(white: 1, alpha: 0.76),
        dark:  UIColor(red: 0.22, green: 0.24, blue: 0.29, alpha: 0.98)
    )
    static let todayMutedFill = adaptive(
        light: UIColor(white: 1, alpha: 0.56),
        dark:  UIColor(red: 0.19, green: 0.21, blue: 0.26, alpha: 0.96)
    )
    static let todayTagFill = adaptive(
        light: UIColor(white: 1, alpha: 0.60),
        dark:  UIColor(red: 0.20, green: 0.22, blue: 0.27, alpha: 0.96)
    )

    // Borders & shadows
    static let todaySurfaceStroke = adaptive(
        light: UIColor(white: 1, alpha: 0.58),
        dark:  UIColor(white: 1, alpha: 0.10)
    )
    static let todayStrongStroke = adaptive(
        light: UIColor(white: 1, alpha: 0.34),
        dark:  UIColor(white: 1, alpha: 0.12)
    )
    static let todayShadow = adaptive(
        light: UIColor(white: 0, alpha: 0.08),
        dark:  UIColor(white: 0, alpha: 0.32)
    )

    // Semantic UI tokens — replace every raw RGB call site
    static let toastInfoAccent    = Color(UIColor.systemBlue)
    static let toastWarningAccent = Color(UIColor.systemOrange)
    static let habitDoneAccent    = Color(UIColor.systemGreen)
    static let pauseControlTint   = Color(UIColor.systemGray2)

    // Rhythm map cells — three distinct semantic levels
    static let rhythmMapEmpty  = Color(UIColor.systemGray5)
    static let rhythmMapSingle = Color(UIColor.systemOrange)
    static let rhythmMapFull   = Color(UIColor.systemBlue)
}
