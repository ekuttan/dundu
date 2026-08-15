import SwiftUI

/// The small vocabulary every screen is built from. Nothing here knows about
/// reminders or events — it is purely the look: a soft grey ground, flat white
/// cards, one big title per screen, and chrome that floats over the content.

// MARK: - Screen chrome

/// Header for a full screen: one large title, an optional line under it, and
/// round actions on the right. This *is* the navigation bar — there is no
/// other one, so the title carries the weight the system bar used to.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Tokens.Typo.largeTitle)
                    .foregroundStyle(Tokens.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(Tokens.Typo.label)
                        .foregroundStyle(Tokens.Colors.quiet)
                }
            }
            Spacer(minLength: Tokens.Spacing.sm)
            trailing
        }
        .padding(.horizontal, Tokens.Layout.gutter)
        .padding(.top, Tokens.Spacing.md)
        .padding(.bottom, Tokens.Spacing.lg)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The round button the system apps put beside a large title: a glyph in a
/// soft circle. `.accent` is the one coral control a screen is allowed.
struct CircleButton: View {
    enum Style {
        case soft      // grey circle, ink glyph — the default
        case accent    // the icon's coral, white glyph
        case onCard    // sits on a card rather than the ground
    }

    let glyph: String
    var style: Style = .soft
    var size: CGFloat = Tokens.Layout.headerButton
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: glyph)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: size, height: size)
                    .background {
                        switch style {
                        case .accent:
                            Circle().fill(Tokens.Colors.accentGradient)
                        case .soft:
                            Circle().fill(Tokens.Colors.fill)
                        case .onCard:
                            Circle().fill(Tokens.Colors.card)
                        }
                    }
                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Tokens.Colors.accent))
                        .offset(x: 4, y: -3)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var foreground: Color {
        style == .accent ? .white : Tokens.Colors.ink
    }
}

// MARK: - Surfaces

/// A card: the one raised surface in the app. Flat white on the grey ground,
/// no border, generous corners. `tint` swaps the fill for a soft wash of a
/// hue, for the places where colour is the information.
struct SoftCard<Content: View>: View {
    var tint: Color?
    var padding: CGFloat = Tokens.Spacing.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(tint.map(Tokens.Colors.blockFill) ?? Tokens.Colors.card)
    }
}

/// The heading line of a card, straight out of the system apps: a tinted
/// glyph, a tinted title, and quiet trailing detail.
struct CardHeader: View {
    let glyph: String
    let title: String
    var tint: Color = Tokens.Colors.accent
    var detail: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(Tokens.Typo.cardTitle)
                .foregroundStyle(tint)
            Spacer(minLength: Tokens.Spacing.sm)
            if let detail {
                Text(detail)
                    .font(Tokens.Typo.label)
                    .foregroundStyle(Tokens.Colors.quiet)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.faint)
            }
        }
    }
}

/// A compact card — the tray's unit. Tinted only by its glyph and its detail
/// line; the surface itself stays white so a row of them reads as one family.
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
                            .font(.system(size: 19, weight: .light))
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
            .padding(.vertical, Tokens.Spacing.md)
            .cardSurface(radius: Tokens.Radius.block)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Actions

/// The one filled control per screen.
struct PillButton: View {
    let title: String
    var glyph: String?
    var style: Style = .primary
    let action: () -> Void

    enum Style {
        case primary   // ink
        case accent    // the icon's coral
        case quiet     // soft grey fill

        var background: AnyShapeStyle {
            switch self {
            case .primary: AnyShapeStyle(Tokens.Colors.ink)
            case .accent: AnyShapeStyle(Tokens.Colors.accentGradient)
            case .quiet: AnyShapeStyle(Tokens.Colors.fill)
            }
        }

        var foreground: Color {
            switch self {
            case .primary: Tokens.Colors.card
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
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(style.foreground)
            .padding(.horizontal, Tokens.Spacing.xl + 4)
            .padding(.vertical, Tokens.Spacing.md + 3)
            .background { Capsule().fill(style.background) }
        }
        .buttonStyle(PressableStyle())
    }
}

/// Everything tappable sinks very slightly.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Screen treatment

extension View {
    /// Grey ground under a stock `Form` or `List`.
    ///
    /// The bespoke screens are hand-built, but the ones that are genuinely
    /// forms — editing a reminder, picking an account — are better served by
    /// the real control than by a reimplementation of it. The grouped style
    /// already draws white cards on grey, which is exactly the language the
    /// rest of the app speaks; this only replaces the backdrop with our own
    /// ground so the greys match.
    func dunduFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Tokens.Colors.ground)
    }

    /// Keeps a scroll view's last row clear of the floating tab bar.
    func clearsFloatingBar() -> some View {
        contentMargins(.bottom, Tokens.Layout.barInset, for: .scrollContent)
    }
}

// MARK: - Navigation

/// The floating bar: destinations in a glass pill on the left, and the two
/// things you *do* — capture by voice, add by hand — stacked in their own
/// glass column in the right corner, the way the system apps now separate
/// "where you are" from "what you're doing".
struct DunduTabBar<Tab: Hashable>: View {
    struct Item: Identifiable {
        let tab: Tab
        let glyph: String
        let title: String
        var badge: Int = 0
        var id: String { title }
    }

    /// A round action in the right-corner stack. Listed top to bottom.
    struct Action: Identifiable {
        let glyph: String
        let title: String
        var isPrimary = false
        let perform: () -> Void
        var id: String { title }
    }

    @Binding var selection: Tab
    let items: [Item]
    var actions: [Action] = []

    private let actionSize: CGFloat = 46

    var body: some View {
        HStack(alignment: .bottom, spacing: Tokens.Spacing.md) {
            tabPill
            if !actions.isEmpty { actionStack }
        }
        .padding(.horizontal, Tokens.Layout.gutter)
        .padding(.bottom, Tokens.Spacing.sm)
    }

    private var tabPill: some View {
        HStack(spacing: 2) {
            ForEach(items) { tabButton($0) }
        }
        .padding(5)
        .floatingSurface(Capsule())
    }

    /// Both actions in one column so the corner reads as a single control,
    /// not two loose buttons. The primary one sits at the bottom, nearest
    /// the thumb.
    private var actionStack: some View {
        VStack(spacing: 6) {
            ForEach(actions) { action in
                Button(action: action.perform) {
                    Image(systemName: action.glyph)
                        .font(.system(size: action.isPrimary ? 20 : 18, weight: .semibold))
                        .foregroundStyle(action.isPrimary ? .white : Tokens.Colors.ink)
                        .frame(width: actionSize, height: actionSize)
                        .background {
                            if action.isPrimary {
                                Circle().fill(Tokens.Colors.accentGradient)
                                    .dunduShadow(Tokens.Shadow.accent)
                            } else {
                                Circle().fill(Color.clear)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(action.title)
            }
        }
        .padding(5)
        .floatingSurface(Capsule())
    }

    private func tabButton(_ item: Item) -> some View {
        let isOn = selection == item.tab
        return Button {
            withAnimation(Tokens.Anim.chrome) { selection = item.tab }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.glyph)
                        .font(.system(size: 18, weight: isOn ? .semibold : .regular))
                        .frame(height: 22)
                    if item.badge > 0 {
                        Circle()
                            .fill(Tokens.Colors.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 6, y: -1)
                    }
                }
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Tokens.Colors.accent : Tokens.Colors.quiet)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if isOn {
                    Capsule().fill(Tokens.Colors.blockFill(Tokens.Colors.accent))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
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
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Tokens.Colors.faint)
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
        .padding(.vertical, Tokens.Spacing.xxl)
    }
}

extension View {
    /// A List row that keeps none of List's decoration: no fill, no
    /// separator, and gutter-width insets so the card inside it lines up
    /// with every other screen.
    func plainRow(inset: Bool = true) -> some View {
        listRowInsets(
            EdgeInsets(
                top: 4,
                leading: inset ? Tokens.Layout.gutter : 0,
                bottom: 4,
                trailing: inset ? Tokens.Layout.gutter : 0
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
