import SwiftUI

/// Design tokens shared by every surface. Kept out of DunduKit on purpose —
/// DunduKit never knows which platform it runs on, and views never define
/// their own magic numbers.
///
/// The language: paper-white ground, almost no chrome, content carried by
/// soft tinted blocks and one piece of hard black type. Anything that isn't
/// content — separators, rails, labels — recedes to a hairline.
enum Tokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let block: CGFloat = 14
        static let card: CGFloat = 16
        static let chip: CGFloat = 12
        static let pill: CGFloat = 22
    }

    enum Anim {
        /// Notch spring: a touch bouncier than the spec's 0.35/0.7 baseline
        /// so the drop reads as the notch growing, with a visible settle.
        static let notchSpring = Animation.spring(response: 0.4, dampingFraction: 0.62)
        static let reduceMotionFallback = Animation.easeInOut(duration: 0.15)
        /// Blocks appearing, the tray reshuffling, a check landing.
        static let content = Animation.spring(response: 0.32, dampingFraction: 0.82)
    }

    /// Type scale. Everything is SF Rounded — the reference's warmth comes
    /// mostly from this one choice.
    enum Typo {
        static func clock(_ size: CGFloat = 64) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        static let clockSuffix = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let screenTitle = Font.system(size: 20, weight: .bold, design: .rounded)
        static let blockTitle = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 15, weight: .medium, design: .rounded)
        static let label = Font.system(size: 13, weight: .medium, design: .rounded)
        /// Hour rail: small, wide-tracked, deliberately quiet.
        static let rail = Font.system(size: 10, weight: .semibold, design: .rounded)
    }

    enum Colors {
        static let overdue = Color.red
        static let dueSoon = Color.orange
        static let meeting = Color.blue

        /// The ground everything sits on.
        static let paper = Color.adaptive(light: .white, dark: Color(white: 0.07))
        /// Raised surfaces — cards, the tray, sheets.
        static let surface = Color.adaptive(light: Color(white: 0.98), dark: Color(white: 0.12))
        /// Hard black type: the clock, the NOW line, the primary pill.
        static let ink = Color.adaptive(light: Color(white: 0.06), dark: Color(white: 0.95))
        /// Hour labels, captions, anything supporting.
        static let quiet = Color.adaptive(light: Color(white: 0.62), dark: Color(white: 0.55))
        /// Gridlines and separators — visible, never assertive.
        static let hairline = Color.adaptive(light: Color(white: 0.91), dark: Color(white: 0.22))

        /// Soft tinted block, the reference's signature. Derived from a base
        /// hue so Google calendar colours keep their identity while all
        /// landing in the same register.
        static func blockFill(_ base: Color) -> Color {
            base.opacity(0.13)
        }
        static func blockStroke(_ base: Color) -> Color {
            base.opacity(0.28)
        }

        /// Lifted from the app icon's gradient so the one warm accent in the
        /// UI is the same coral the user sees on their home screen.
        static let accent = Color(red: 0.97, green: 0.42, blue: 0.40)
        static let accentWarm = Color(red: 0.99, green: 0.64, blue: 0.38)
        static let accentGradient = LinearGradient(
            colors: [accent, accentWarm],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Category hues. Muted on purpose: the tint is 13% of this.
        static let hueMeeting = Color(red: 0.35, green: 0.40, blue: 0.92)
        static let hueTask = Color(red: 0.16, green: 0.55, blue: 0.95)
        static let hueTravel = Color(red: 0.55, green: 0.40, blue: 0.90)
        static let hueUrgent = Color(red: 0.95, green: 0.35, blue: 0.30)
        static let hueDone = Color(red: 0.20, green: 0.72, blue: 0.45)
    }
}

extension Color {
    /// One place for light/dark pairs. SwiftUI has no cross-platform dynamic
    /// colour initialiser, so each platform resolves it with its own.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #else
        light
        #endif
    }
}
