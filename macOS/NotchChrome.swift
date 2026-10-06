import SwiftUI

/// The notch panel's own design system.
///
/// Deliberately separate from `Tokens`: the panel is a dark HUD that hangs
/// off the hardware notch and is read at a glance from a metre away, so it
/// wants heavier type, flatter surfaces and tighter contrast than the app's
/// documents do. Mixing the two vocabularies is what made the old panel look
/// like a settings sheet that had wandered up the screen.
enum NP {
    enum C {
        /// Pure black so the panel and the physical notch are one shape.
        static let panel = Color.black
        static let card = Color(white: 0.085)
        static let cardRaised = Color(white: 0.13)
        static let stroke = Color.white.opacity(0.07)
        static let strokeStrong = Color.white.opacity(0.14)

        static let text = Color.white
        static let dim = Color.white.opacity(0.55)
        static let faint = Color.white.opacity(0.32)

        static let good = Color(red: 0.26, green: 0.84, blue: 0.47)
        static let warn = Color(red: 1.00, green: 0.70, blue: 0.24)
        static let bad = Color(red: 0.98, green: 0.38, blue: 0.36)
        static let info = Color(red: 0.36, green: 0.62, blue: 1.00)
        /// The heatmap and streak hue. Warm on purpose — it is the one place
        /// in Dundu that is a chart rather than chrome, and a blue grid on a
        /// black panel disappears.
        static let ember = Color(red: 1.00, green: 0.55, blue: 0.40)
    }

    enum R {
        static let card: CGFloat = 16
        static let chip: CGFloat = 10
        static let panel: CGFloat = 30
    }

    enum F {
        static let greeting = Font.system(size: 30, weight: .bold)
        static let pageTitle = Font.system(size: 14, weight: .medium)
        static let value = Font.system(size: 27, weight: .bold).monospacedDigit()
        static let valueSmall = Font.system(size: 17, weight: .semibold).monospacedDigit()
        static let row = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 10.5)
        static let chip = Font.system(size: 10.5, weight: .medium)
        static let label = Font.system(size: 9, weight: .semibold)
    }

    /// Page padding. The dock's capsule is inset further so the panel reads
    /// as the larger surface.
    static let gutter: CGFloat = 20
    static let gridGap: CGFloat = 10
}

// MARK: - Primitives

/// The uppercase, letter-spaced caps every card in the reference leads with.
struct NPLabel: View {
    let text: String
    var icon: String?
    var tint: Color = NP.C.dim

    init(_ text: String, icon: String? = nil, tint: Color = NP.C.dim) {
        self.text = text
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text.uppercased())
                .font(NP.F.label)
                .tracking(0.7)
        }
        .foregroundStyle(tint)
    }
}

/// The panel's one container. Everything on a page lives in one of these.
struct NPCard<Content: View>: View {
    var padding: CGFloat = 13
    var fill: Color = NP.C.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: NP.R.card, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NP.R.card, style: .continuous)
                    .strokeBorder(NP.C.stroke, lineWidth: 1)
            )
    }
}

/// Label on top, a number you can read from across the room, a quiet line of
/// context underneath.
struct NPStatCard: View {
    let label: String
    var icon: String? = nil
    let value: String
    var caption: String? = nil
    var valueTint: Color = NP.C.text
    var trailing: AnyView? = nil

    var body: some View {
        NPCard {
            VStack(alignment: .leading, spacing: 0) {
                NPLabel(label, icon: icon)
                Spacer(minLength: 6)
                HStack(alignment: .bottom, spacing: 8) {
                    Text(value)
                        .font(NP.F.value)
                        .foregroundStyle(valueTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let trailing {
                        Spacer(minLength: 0)
                        trailing
                    }
                }
                if let caption {
                    Text(caption)
                        .font(NP.F.caption)
                        .foregroundStyle(NP.C.faint)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
        }
    }
}

/// Primary is white-on-black, secondary is the reverse — straight from the
/// reference, and it keeps one obvious action per card.
struct NPButton: View {
    enum Kind { case primary, secondary, danger }

    let title: String
    var icon: String?
    var kind: Kind = .secondary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                }
                Text(title).font(NP.F.chip)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(kind == .secondary ? NP.C.stroke : .clear))
        }
        .buttonStyle(.plain)
        // Without this a button in a row with a Spacer gets compressed into
        // "J…" rather than "Join".
        .fixedSize()
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .secondary: NP.C.text
        case .danger: NP.C.bad
        }
    }

    private var background: Color {
        switch kind {
        case .primary: hovering ? .white : Color(white: 0.95)
        case .secondary: Color(white: hovering ? 0.22 : 0.16)
        case .danger: NP.C.bad.opacity(hovering ? 0.26 : 0.16)
        }
    }
}

/// The tool switcher: a dark trough with one lit pill in it.
struct NPSegmented<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    var icon: (Item) -> String?
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button { selection = item } label: {
                    HStack(spacing: 4) {
                        if let name = icon(item) {
                            Image(systemName: name).font(.system(size: 9, weight: .semibold))
                        }
                        Text(title(item)).font(NP.F.chip.weight(on ? .semibold : .medium))
                    }
                    .foregroundStyle(on ? .black : NP.C.dim)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        if on { Capsule().fill(Color(white: 0.96)) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(white: 0.12)))
        .overlay(Capsule().strokeBorder(NP.C.stroke))
    }
}

/// A dot and a word — "3 due", "2 agents live".
struct NPStatusChip: View {
    let text: String
    var tint: Color = NP.C.good

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(text).font(NP.F.chip).foregroundStyle(NP.C.dim)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(white: 0.12)))
        .overlay(Capsule().strokeBorder(NP.C.stroke))
    }
}

/// Page header: a quiet title on the left, whatever the page needs on the
/// right. Every page uses it, so the panel never jumps between layouts.
struct NPPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(NP.F.pageTitle)
                .foregroundStyle(NP.C.dim)
            if let subtitle {
                Text(subtitle)
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.faint)
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(height: 26)
    }
}

extension NPPageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A ring gauge — CPU, memory, battery on the dashboard.
struct NPRing: View {
    let fraction: Double
    let label: String
    let caption: String
    var tint: Color = NP.C.good

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: max(0.01, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(label)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NP.C.text)
            }
            .frame(width: 42, height: 42)
            Text(caption)
                .font(NP.F.label)
                .tracking(0.6)
                .foregroundStyle(NP.C.faint)
        }
    }
}
