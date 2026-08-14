import SwiftUI

/// The small vocabulary every screen is built from. Nothing here knows about
/// reminders or events — it is purely the look: paper ground, soft tinted
/// blocks, one hard black pill, hairline everything else.

// MARK: - Screen chrome

/// Header for a full screen: a glyph, a title, and one optional round action
/// on the right. Replaces the navigation bar — the reference has none.
struct ScreenHeader<Trailing: View>: View {
    let glyph: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.sm) {
            Image(systemName: glyph)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.Colors.ink)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Tokens.Typo.screenTitle)
                    .foregroundStyle(Tokens.Colors.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Tokens.Typo.label)
                        .foregroundStyle(Tokens.Colors.quiet)
                }
            }
            Spacer(minLength: Tokens.Spacing.md)
            trailing
        }
        .padding(.horizontal, Tokens.Spacing.xl)
        .padding(.vertical, Tokens.Spacing.md)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(glyph: String, title: String, subtitle: String? = nil) {
        self.init(glyph: glyph, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The round warm button in the reference's top-right corner. Carries the
/// icon's coral so the accent appears exactly once per screen.
struct RoundAccentButton: View {
    let glyph: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Tokens.Colors.accentGradient)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: glyph)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Tokens.Colors.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.white))
                        .offset(x: 4, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Surfaces

/// A soft raised panel. Used for the tray, sheets, and anywhere a list used
/// to have a grouped background.
struct SoftCard<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Tokens.Spacing.lg)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .fill(tint.map(Tokens.Colors.blockFill) ?? Tokens.Colors.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                            .stroke(
                                tint.map(Tokens.Colors.blockStroke) ?? Tokens.Colors.hairline,
                                lineWidth: 1
                            )
                    }
            }
    }
}

/// A compact tinted chip — the tray's unit, and the Lists screen's row.
struct TrayChip: View {
    let title: String
    var detail: String?
    var glyph: String
    var tint: Color
    var isCompleted: Bool = false
    let onToggle: (() -> Void)?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Tokens.Spacing.sm) {
                if let onToggle {
                    Button(action: onToggle) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isCompleted ? Tokens.Colors.hueDone : tint)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: glyph)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Tokens.Typo.blockTitle)
                        .foregroundStyle(Tokens.Colors.ink)
                        .strikethrough(isCompleted, color: Tokens.Colors.quiet)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.sm + 2)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                    .fill(Tokens.Colors.blockFill(tint))
                    .overlay {
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                            .stroke(Tokens.Colors.blockStroke(tint), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Actions

/// The one hard black control per screen.
struct PillButton: View {
    let title: String
    var glyph: String?
    var style: Style = .primary
    let action: () -> Void

    enum Style {
        case primary   // black on paper
        case accent    // the icon's coral
        case quiet     // hairline outline

        var background: AnyShapeStyle {
            switch self {
            case .primary: AnyShapeStyle(Tokens.Colors.ink)
            case .accent: AnyShapeStyle(Tokens.Colors.accentGradient)
            case .quiet: AnyShapeStyle(Color.clear)
            }
        }

        var foreground: Color {
            switch self {
            case .primary: Tokens.Colors.paper
            case .accent: .white
            case .quiet: Tokens.Colors.ink
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Spacing.sm) {
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(style.foreground)
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.vertical, Tokens.Spacing.md + 2)
            .background {
                Capsule().fill(style.background)
                    .overlay {
                        if case .quiet = style {
                            Capsule().stroke(Tokens.Colors.hairline, lineWidth: 1)
                        }
                    }
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// Everything tappable sinks very slightly. The reference is static, but a
/// screen this quiet needs its feedback somewhere.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Screen treatment

extension View {
    /// Paper ground under a stock `Form` or `List`.
    ///
    /// The bespoke screens are hand-built, but the ones that are genuinely
    /// forms — editing a reminder, picking an account — are better served by
    /// the real control than by a reimplementation of it. This drops the
    /// grouped-grey backdrop so they sit on the same paper as everything
    /// else; `fontDesign(.rounded)` and the accent tint come down from the
    /// root, so the rows already speak the same language.
    func dunduFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Tokens.Colors.paper)
    }
}

// MARK: - Navigation

/// The system tab bar brings its own material, blur and tint — all of which
/// fight a paper-white screen. This is the same four destinations drawn in
/// the app's own language: ink for where you are, hairline for the rest.
struct DunduTabBar<Tab: Hashable>: View {
    struct Item: Identifiable {
        let tab: Tab
        let glyph: String
        let title: String
        var badge: Int = 0
        var id: String { title }
    }

    @Binding var selection: Tab
    /// Split evenly either side of the centre button. Four reads best.
    let items: [Item]
    /// The raised centre action — adding something, from any tab.
    var centreGlyph = "plus"
    var onCentre: () -> Void = {}

    private var half: Int { (items.count + 1) / 2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.prefix(half)) { tabButton($0) }
            // Room for the raised button to sit in. Height is pinned:
            // an unconstrained Color.clear is greedy and would stretch the
            // whole bar to fill the screen.
            Color.clear.frame(width: 72, height: 1)
            ForEach(items.suffix(from: min(half, items.count))) { tabButton($0) }
        }
        .padding(.top, Tokens.Spacing.sm + 2)
        .background(alignment: .top) {
            Rectangle()
                .fill(Tokens.Colors.hairline)
                .frame(height: 1)
        }
        .background(Tokens.Colors.paper)
        // An overlay, not a stack member: the raised button hangs above the
        // bar without adding its overhang to the bar's height, which would
        // otherwise push the whole screen up by the offset.
        .overlay(alignment: .top) {
            Button(action: onCentre) {
                Image(systemName: centreGlyph)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Tokens.Colors.accentGradient))
                    .background(
                        Circle()
                            .fill(Tokens.Colors.paper)
                            .frame(width: 64, height: 64)
                    )
                    .shadow(color: Tokens.Colors.accent.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(PressableStyle())
            .offset(y: -24)
        }
    }

    private func tabButton(_ item: Item) -> some View {
        Button {
            selection = item.tab
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.glyph)
                        .font(.system(size: 17, weight: selection == item.tab ? .semibold : .regular))
                    if item.badge > 0 {
                        Circle()
                            .fill(Tokens.Colors.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 5, y: -2)
                    }
                }
                .frame(height: 20)
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selection == item.tab ? Tokens.Colors.ink : Tokens.Colors.quiet)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A time-of-day greeting. The home screen says hello before it says work.
enum Greeting {
    static func now(_ date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<5: "Still up?"
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }
}

// MARK: - Empty states

/// Replaces ContentUnavailableView, which brings its own grey list styling.
struct QuietEmptyState: View {
    let glyph: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: glyph)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Tokens.Colors.hairline)
            Text(title)
                .font(Tokens.Typo.body)
                .foregroundStyle(Tokens.Colors.quiet)
            if let message {
                Text(message)
                    .font(Tokens.Typo.label)
                    .foregroundStyle(Tokens.Colors.quiet.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.xl)
    }
}

extension View {
    /// A List row that keeps none of List's decoration: no inset, no fill,
    /// no separator unless asked for. Lets the rows look hand-built while
    /// still getting swipe actions, which only exist inside a List.
    func plainRow(separator: Bool = false) -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(separator ? .visible : .hidden)
            .listRowSeparatorTint(Tokens.Colors.hairline)
            .alignmentGuide(.listRowSeparatorLeading) { _ in Tokens.Spacing.xl + 34 }
    }
}
