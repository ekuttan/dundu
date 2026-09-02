import SwiftUI

/// Design tokens shared by every surface. Kept out of DunduKit on purpose —
/// DunduKit never knows which platform it runs on, and views never define
/// their own magic numbers.
///
/// The language follows the current Apple system apps: a soft grey ground,
/// content carried by flat white cards with generous corners, type doing the
/// hierarchy (one big title per screen), and chrome that floats over the
/// content instead of framing it. Borders are the exception, not the rule —
/// a card is told apart from the ground by its fill, not by an outline.
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
        static let chip: CGFloat = 14
        static let block: CGFloat = 18
        static let card: CGFloat = 22
        static let sheet: CGFloat = 28
    }

    enum Layout {
        /// Screen margin. Everything full-width lines up on this.
        static let gutter: CGFloat = 20
        /// Minimum comfortable tap target.
        static let control: CGFloat = 44
        /// Round chrome buttons in a header.
        static let headerButton: CGFloat = 38
        /// Every element of the floating bar is this tall — the tab pill and
        /// the action capsule beside it. They sat at different heights and
        /// read as unrelated pieces.
        static let barHeight: CGFloat = 56
        /// How much room the floating tab bar needs at the bottom of a
        /// scroll view so the last row clears it. Measured from the tallest
        /// thing down there, which is the floating action button riding above
        /// the row, not the pill itself.
        static let barInset: CGFloat = 152
    }

    /// Shadows exist only under things that genuinely float — the tab bar,
    /// the accessory stack, the one accent button. Cards sit flat on the
    /// ground and are read by their fill.
    enum Shadow {
        struct Spec {
            var color: Color
            var radius: CGFloat
            var y: CGFloat
        }

        static let floating = Spec(color: .black.opacity(0.07), radius: 10, y: 3)
        static let accent = Spec(color: .black.opacity(0.10), radius: 8, y: 3)
    }

    enum Anim {
        /// Notch spring: a touch bouncier than the spec's 0.35/0.7 baseline
        /// so the drop reads as the notch growing, with a visible settle.
        static let notchSpring = Animation.spring(response: 0.4, dampingFraction: 0.62)
        static let reduceMotionFallback = Animation.easeInOut(duration: 0.15)
        /// Blocks appearing, the tray reshuffling, a check landing.
        static let content = Animation.spring(response: 0.32, dampingFraction: 0.82)
        /// Tab changes and other chrome: quicker, no bounce.
        static let chrome = Animation.spring(response: 0.28, dampingFraction: 0.9)
    }

    /// Type scale, in the system font. SF Rounded was chosen for an earlier,
    /// warmer language; the app now follows the system apps, and rounded type
    /// beside stock controls reads as a different app pasted in.
    ///
    /// The screen title is deliberately much larger than anything under it: on
    /// these screens the title is the only piece of navigation there is.
    enum Typo {
        static func clock(_ size: CGFloat = 64) -> Font {
            .system(size: size, weight: .bold)
        }
        static let clockSuffix = Font.system(size: 22, weight: .semibold)
        /// The one big title at the top of a screen.
        static let largeTitle = Font.system(size: 34, weight: .bold)
        /// Titles inside sheets and other secondary surfaces.
        static let screenTitle = Font.system(size: 20, weight: .bold)
        /// The coloured heading line of a card.
        static let cardTitle = Font.system(size: 17, weight: .semibold)
        /// A section heading over a group of cards.
        static let sectionTitle = Font.system(size: 15, weight: .semibold)
        static let blockTitle = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 16, weight: .medium)
        static let label = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 12, weight: .medium)
        /// Hour rail: small, wide-tracked, deliberately quiet.
        static let rail = Font.system(size: 10, weight: .semibold)
    }

    enum Colors {
        static let overdue = Color.red
        static let dueSoon = Color.orange
        static let meeting = Color.blue

        /// The ground everything sits on. White, and the same white as a
        /// card: content is separated by space, not by a change of surface.
        /// A list of reminders reads as one page rather than a stack of tiles.
        static let ground = Color.adaptive(light: .white, dark: Color(white: 0.07))
        /// A card: the surface content actually lives on.
        static let card = Color.adaptive(light: .white, dark: Color(white: 0.13))
        /// A quieter fill used *inside* a card, and for chrome buttons —
        /// chips, wells, the unselected segment of a filter row.
        static let fill = Color.adaptive(light: Color(white: 0.925), dark: Color(white: 0.20))

        /// Older names, kept so the Mac surfaces and any stray call site keep
        /// meaning what they meant: `paper` is a card, `surface` is a fill.
        static let paper = card
        static let surface = fill

        /// Primary type: the title, a reminder's name, the clock.
        static let ink = Color.adaptive(light: Color(white: 0.06), dark: Color(white: 0.96))
        /// Supporting type: dates, counts, captions.
        static let quiet = Color.adaptive(light: Color(white: 0.47), dark: Color(white: 0.62))
        /// Third rank: chevrons, empty-state glyphs, placeholder marks.
        static let faint = Color.adaptive(light: Color(white: 0.72), dark: Color(white: 0.42))
        /// The rare separator that still earns its place.
        static let hairline = Color.adaptive(light: Color(white: 0.89), dark: Color(white: 0.24))

        /// Soft tinted block, used where colour *is* the information — a
        /// meeting on the timeline, a tinted glyph well.
        static func blockFill(_ base: Color) -> Color {
            base.opacity(0.14)
        }
        static func blockStroke(_ base: Color) -> Color {
            base.opacity(0.24)
        }

        /// The one accent, and it is deliberately quiet. Chrome is ink and
        /// grey — a selected tab, a primary button, a heading — so the blue is
        /// left to mean "this does something": the floating add button, a
        /// link, a live recording, a badge worth noticing.
        ///
        /// Flat, not a gradient. A gradient reads as decoration, and this
        /// colour is meant to read as a signal.
        static let accent = Color(red: 0.20, green: 0.50, blue: 0.93)
        static let accentWarm = Color(red: 0.34, green: 0.60, blue: 0.96)
        /// Kept as a gradient type so call sites need no shape change, but
        /// the two stops sit close enough together to read as one colour.
        static let accentGradient = LinearGradient(
            colors: [accent, accentWarm],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Category hues. Muted on purpose: the tint is 14% of this.
        static let hueMeeting = Color(red: 0.35, green: 0.40, blue: 0.92)
        static let hueTask = Color(red: 0.16, green: 0.55, blue: 0.95)
        static let hueTravel = Color(red: 0.55, green: 0.40, blue: 0.90)
        static let hueUrgent = Color(red: 0.95, green: 0.35, blue: 0.30)
        static let hueDone = Color(red: 0.20, green: 0.72, blue: 0.45)
    }
}

extension View {
    func dunduShadow(_ spec: Tokens.Shadow.Spec) -> some View {
        shadow(color: spec.color, radius: spec.radius, y: spec.y)
    }

    /// A flat card on the ground: fill, big corners, no border. The single
    /// surface treatment the whole app is built from.
    func cardSurface(
        _ fill: Color = Tokens.Colors.card,
        radius: CGFloat = Tokens.Radius.card
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
        }
    }

    /// Chrome that hovers over content — the tab bar and its accessories.
    /// Material rather than a solid fill, so scrolling content shows through.
    func floatingSurface<S: Shape>(_ shape: S) -> some View {
        background(.regularMaterial, in: shape)
            .overlay {
                shape.stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            }
            .dunduShadow(Tokens.Shadow.floating)
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
