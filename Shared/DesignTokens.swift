import SwiftUI

enum Tokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let chip: CGFloat = 12
        static let block: CGFloat = 16
        static let card: CGFloat = 20
        static let sheet: CGFloat = 28
    }

    enum Layout {
        static let gutter: CGFloat = 20
        static let control: CGFloat = 44
        static let headerButton: CGFloat = 44
        static let scrollBottomPadding: CGFloat = 16
    }

    enum Anim {
        static let notchSpring = Animation.spring(response: 0.4, dampingFraction: 0.62)
        static let reduceMotionFallback = Animation.easeInOut(duration: 0.15)
        static let content = Animation.easeOut(duration: 0.22)
    }

    enum Typo {
        static func clock(_ size: CGFloat = 64) -> Font {
            .system(size: size, weight: .regular)
        }
        static let clockSuffix = Font.system(.title3)
        static let largeTitle = Font.system(.largeTitle).weight(.bold)
        static let screenTitle = Font.system(.title2).weight(.bold)
        static let cardTitle = Font.system(.headline)
        static let sectionTitle = Font.system(.subheadline).weight(.semibold)
        static let body = Font.system(.body)
        static let blockTitle = Font.system(.subheadline).weight(.semibold)
        static let label = Font.system(.subheadline)
        static let caption = Font.system(.caption)
        static let rail = Font.system(.caption2).weight(.medium)
    }

    enum Colors {
        static let onAccent = Color.white
        static let overdue = Color.red
        static let dueSoon = Color.orange
        static let meeting = Color.blue

        #if os(iOS)
        static let ground = Color(uiColor: .systemGroupedBackground)
        static let card = Color(uiColor: .secondarySystemGroupedBackground)
        static let fill = Color(uiColor: .tertiarySystemFill)
        static let hairline = Color(uiColor: .separator)
        #else
        static let ground = Color(nsColor: .windowBackgroundColor)
        static let card = Color(nsColor: .controlBackgroundColor)
        static let fill = Color(nsColor: .quaternaryLabelColor).opacity(0.15)
        static let hairline = Color(nsColor: .separatorColor)
        #endif
        static let paper = card
        static let surface = fill
        static let ink = Color.primary
        static let quiet = Color.secondary
        static let faint = Color.secondary.opacity(0.7)

        static func blockFill(_ base: Color) -> Color {
            base.opacity(0.08)
        }
        static func blockStroke(_ base: Color) -> Color {
            base.opacity(0.24)
        }

        static let accent = Color.blue
        static let accentWarm = accent
        static let accentGradient = LinearGradient(
            colors: [accent, accentWarm],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let hueMeeting = Color(red: 0.43, green: 0.43, blue: 0.72)
        static let hueTask = accent
        static let hueTravel = Color(red: 0.55, green: 0.40, blue: 0.90)
        static let hueUrgent = Color(red: 0.95, green: 0.35, blue: 0.30)
        static let hueDone = Color(red: 0.20, green: 0.72, blue: 0.45)
    }
}

extension View {
    func cardSurface(
        _ fill: Color = Tokens.Colors.card,
        radius: CGFloat = Tokens.Radius.card
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
        }
    }


}

extension Color {
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
