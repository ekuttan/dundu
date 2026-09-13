import SwiftUI


// MARK: - Screen chrome

struct ScreenHeader<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Spacing.md))
        layout {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(title)
                    .font(Tokens.Typo.largeTitle)
                    .foregroundStyle(Tokens.Colors.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(Tokens.Typo.label)
                        .foregroundStyle(Tokens.Colors.quiet)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Tokens.Spacing.sm) }
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Layout.gutter)
        .padding(.top, Tokens.Spacing.lg)
        .padding(.bottom, Tokens.Spacing.xl)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct CircleButton: View {
    enum Style {
        case soft      // grey circle, ink glyph — the default
        case accent    // filled accent action
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
                        .font(.system(size: 10, weight: .bold))
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
        style == .accent ? Tokens.Colors.onAccent : Tokens.Colors.ink
    }
}

// MARK: - Surfaces

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

struct CardHeader: View {
    let glyph: String
    let title: String
    var tint: Color = Tokens.Colors.accent
    var detail: String?
    var detailTint: Color = Tokens.Colors.quiet
    var showsChevron = false

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(Tokens.Typo.label)
                .foregroundStyle(tint)
            Spacer(minLength: Tokens.Spacing.sm)
            if let detail {
                Text(detail)
                    .font(Tokens.Typo.label)
                    .foregroundStyle(detailTint)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.faint)
            }
        }
    }
}

struct TrayChip: View {
    let title: String
    var detail: String?
    var glyph: String
    var tint: Color
    var isCompleted: Bool = false
    let onToggle: (() -> Void)?
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(tint)
                        .frame(width: Tokens.Layout.control, height: Tokens.Layout.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCompleted ? "Reopen reminder" : "Complete reminder")
            } else {
                Image(systemName: glyph)
                    .foregroundStyle(tint)
                    .frame(width: Tokens.Layout.control)
            }
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(title)
                        .font(Tokens.Typo.blockTitle)
                        .foregroundStyle(Tokens.Colors.ink)
                        .strikethrough(isCompleted, color: Tokens.Colors.quiet)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detail ?? "Anytime")
                        .font(Tokens.Typo.caption)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                .frame(minHeight: Tokens.Layout.control, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Tokens.Spacing.sm)
        .padding(.trailing, Tokens.Spacing.sm)
        .frame(maxWidth: 300, alignment: .leading)
        .cardSurface(radius: Tokens.Radius.block)
    }

}

// MARK: - Actions

struct PillButton: View {
    let title: String
    var glyph: String?
    var style: Style = .primary
    let action: () -> Void

    enum Style {
        case primary   // ink
        case accent    // filled accent action
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
            case .accent: Tokens.Colors.onAccent
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
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(style.foreground)
            .padding(.horizontal, Tokens.Spacing.xl + 4)
            .padding(.vertical, Tokens.Spacing.md + 3)
            .background { Capsule().fill(style.background) }
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Screen treatment

extension View {
    func dunduFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Tokens.Colors.ground)
    }

    func dunduScrollMargins() -> some View {
        contentMargins(.bottom, Tokens.Layout.scrollBottomPadding, for: .scrollContent)
    }
}

// MARK: - Navigation

/// Independent navigation stacks with three grouped destinations and a
/// separate capture action. The voice control is an action, never a fake tab.
struct DunduWorkspace: View {
    @Binding var selection: AppTab
    var inboxCount: Int
    var onAdd: () -> Void
    var onRecord: () -> Void
    var onSettings: () -> Void

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ListsView(onSettings: onSettings)
                    .modifier(CaptureToolbar(onAdd: onAdd))
            }
            .tabItem { Label("Reminders", systemImage: "checklist") }
            .tag(AppTab.lists)

            NavigationStack {
                TodayView(inboxCount: inboxCount) { selection = .inbox }
                    .modifier(CaptureToolbar(onAdd: onAdd))
            }
            .tabItem { Label("Today", systemImage: "calendar") }
            .tag(AppTab.today)

            NavigationStack {
                InboxView()
                    .modifier(CaptureToolbar(onAdd: onAdd))
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .tag(AppTab.inbox)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            WorkspaceDock(selection: $selection, inboxCount: inboxCount, onRecord: onRecord)
                .frame(maxWidth: 520)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct CaptureToolbar: ViewModifier {
    let onAdd: () -> Void

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 74) }
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add reminder", systemImage: "plus", action: onAdd)
                }
            }
    }
}

private struct WorkspaceDock: View {
    @Binding var selection: AppTab
    let inboxCount: Int
    let onRecord: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) { controls }
        } else {
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                destination(.lists, title: "Reminders", icon: "checklist")
                destination(.today, title: "Today", icon: "calendar")
                destination(.inbox, title: "Inbox", icon: "tray")
            }
            .padding(5)
            .modifier(DockSurface(reduceTransparency: reduceTransparency))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Navigation")

            Button(action: onRecord) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 58, height: 58)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(Tokens.Colors.ink)
            .modifier(DockSurface(reduceTransparency: reduceTransparency))
            .accessibilityLabel("Record a reminder")
            .accessibilityHint("Opens voice capture")
        }
    }

    private func destination(_ tab: AppTab, title: String, icon: String) -> some View {
        let selected = selection == tab
        return Button { selection = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: selected ? .semibold : .regular))
                    .frame(height: 21)
                    .overlay(alignment: .topTrailing) {
                        if tab == .inbox, inboxCount > 0 {
                            Text(inboxCount > 99 ? "99+" : "\(inboxCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(.red, in: Capsule())
                                .offset(x: 12, y: -5)
                        }
                    }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(selected ? Tokens.Colors.accent : Tokens.Colors.quiet)
            .background {
                if selected { Capsule().fill(.primary.opacity(0.07)) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(tab == .inbox && inboxCount > 0 ? "\(inboxCount) items to review" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DockSurface: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Tokens.Colors.card, in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        }
    }
}

// MARK: - Empty states

struct QuietEmptyState: View {
    let glyph: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: glyph)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Tokens.Colors.accent)
                .padding(.bottom, Tokens.Spacing.sm)
            Text(title)
                .font(Tokens.Typo.cardTitle)
                .foregroundStyle(Tokens.Colors.ink)
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
