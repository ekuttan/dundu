import SwiftUI

/// One thing placed on the day: a meeting, or a reminder that has a time.
/// Deliberately a plain value — the timeline never touches SwiftData, so it
/// previews and lays out without a store.
struct TimelineEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case event
        case reminder
    }

    let id: UUID
    var title: String
    var subtitle: String?
    var start: Date
    var end: Date
    var kind: Kind
    var glyph: String
    var tint: Color
    var isCompleted: Bool = false
    /// Meetings with a conference link get a Join affordance.
    var joinURL: URL?

    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
}

/// The day as a vertical strip: hour rail on the left, blocks placed at their
/// real times, and a live NOW rule. Everything else on Today hangs off this.
struct DayTimeline: View {
    let entries: [TimelineEntry]
    /// The day being shown, and the current moment when that day is today.
    let now: Date
    /// Off on any other day — a NOW rule on Thursday's page is a lie.
    var isToday = true
    var onTap: (TimelineEntry) -> Void
    var onToggle: (TimelineEntry) -> Void
    /// Tapping a meeting joins it, so editing moves to a long press.
    var onEdit: (TimelineEntry) -> Void = { _ in }

    /// One hour of wall clock. Tall enough that a 30-minute meeting is still
    /// a readable block rather than a stripe.
    private let hourHeight: CGFloat = 76
    private let railWidth: CGFloat = 46
    /// A reminder is an instant, not a span — give it a block worth reading.
    private let minimumBlockHeight: CGFloat = 46

    private var dayStart: Date { Calendar.current.startOfDay(for: now) }
    private var contentHeight: CGFloat { 24 * hourHeight }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                GeometryReader { geo in
                    let laneWidth = geo.size.width - railWidth
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        ForEach(placed(in: laneWidth)) { placement in
                            TimelineBlock(
                                entry: placement.entry,
                                onTap: { onTap(placement.entry) },
                                onToggle: { onToggle(placement.entry) },
                                onEdit: { onEdit(placement.entry) }
                            )
                            .frame(width: placement.width, height: placement.height)
                            .offset(x: railWidth + placement.x, y: placement.y)
                        }
                        if entries.isEmpty {
                            // An empty day should say so once, next to the
                            // moment it is empty at — not fill the strip.
                            Text(isToday ? "Nothing scheduled" : "Nothing this day")
                                .font(Tokens.Typo.label)
                                .foregroundStyle(Tokens.Colors.quiet)
                                .offset(x: railWidth + Tokens.Spacing.sm, y: y(for: now) + 14)
                        }
                        if isToday {
                            nowRule(width: geo.size.width)
                        }
                        // Scroll target: parks the current moment near the
                        // bottom of the viewport, the way the reference reads.
                        Color.clear
                            .frame(height: 1)
                            .offset(y: y(for: now))
                            .id(Self.nowAnchor)
                    }
                    .frame(width: geo.size.width, height: contentHeight, alignment: .topLeading)
                }
                .frame(height: contentHeight)
            }
            .onAppear {
                proxy.scrollTo(Self.nowAnchor, anchor: UnitPoint(x: 0.5, y: 0.82))
            }
        }
    }

    private static let nowAnchor = "now-anchor"

    // MARK: - Grid

    private var hourGrid: some View {
        ForEach(0..<24, id: \.self) { hour in
            HStack(alignment: .center, spacing: Tokens.Spacing.sm) {
                Text(Self.railLabel(hour))
                    .font(Tokens.Typo.rail)
                    .tracking(0.4)
                    .foregroundStyle(Tokens.Colors.quiet)
                    .frame(width: railWidth - Tokens.Spacing.sm, alignment: .leading)
                Rectangle()
                    .fill(Tokens.Colors.hairline)
                    .frame(height: 1)
            }
            .offset(y: CGFloat(hour) * hourHeight)
        }
    }

    private static func railLabel(_ hour: Int) -> String {
        switch hour {
        case 0: "12 AM"
        case 12: "12 PM"
        case ..<12: "\(hour) AM"
        default: "\(hour - 12) PM"
        }
    }

    // MARK: - NOW

    private func nowRule(width: CGFloat) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Text("NOW")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Tokens.Colors.ink)
                .frame(width: railWidth - Tokens.Spacing.sm, alignment: .leading)
            Circle()
                .fill(Tokens.Colors.ink)
                .frame(width: 5, height: 5)
            Rectangle()
                .fill(Tokens.Colors.ink)
                .frame(height: 1.5)
            Circle()
                .fill(Tokens.Colors.ink)
                .frame(width: 5, height: 5)
        }
        .frame(width: width)
        .offset(y: y(for: now))
    }

    // MARK: - Placement

    private func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * hourHeight
    }

    private struct Placement: Identifiable {
        let entry: TimelineEntry
        let x: CGFloat
        let width: CGFloat
        let y: CGFloat
        let height: CGFloat
        var id: UUID { entry.id }
    }

    /// Greedy lane packing: overlapping blocks sit side by side rather than
    /// on top of each other. A day rarely needs more than three lanes, and
    /// past that the blocks get narrow but stay readable.
    private func placed(in available: CGFloat) -> [Placement] {
        let sorted = entries.sorted { $0.start < $1.start }
        var laneEnds: [Date] = []
        var lanes: [Int] = []

        for entry in sorted {
            let blockEnd = entry.start.addingTimeInterval(
                max(entry.duration, Double(minimumBlockHeight / hourHeight) * 3600)
            )
            if let free = laneEnds.firstIndex(where: { $0 <= entry.start }) {
                laneEnds[free] = blockEnd
                lanes.append(free)
            } else {
                laneEnds.append(blockEnd)
                lanes.append(laneEnds.count - 1)
            }
        }

        let laneCount = max(laneEnds.count, 1)
        let gutter: CGFloat = 6
        let usable = max(available - Tokens.Spacing.lg, 80)
        let laneWidth = (usable - gutter * CGFloat(laneCount - 1)) / CGFloat(laneCount)

        return zip(sorted, lanes).map { entry, lane in
            Placement(
                entry: entry,
                x: CGFloat(lane) * (laneWidth + gutter),
                width: laneWidth,
                y: y(for: entry.start),
                height: max(y(for: entry.end) - y(for: entry.start), minimumBlockHeight)
            )
        }
    }
}

/// A single soft tinted block: glyph and label at the top-left, and — for
/// reminders — a check riding the right edge, exactly like the reference.
struct TimelineBlock: View {
    let entry: TimelineEntry
    let onTap: () -> Void
    let onToggle: () -> Void
    var onEdit: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: entry.glyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.tint)
                Text(entry.title)
                    .font(Tokens.Typo.blockTitle)
                    .foregroundStyle(Tokens.Colors.ink)
                    .strikethrough(entry.isCompleted, color: Tokens.Colors.quiet)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tokens.Colors.quiet)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.sm + 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // No outline: the fill alone separates a block from the grid,
            // which is what keeps a busy day from turning into a mesh.
            .cardSurface(Tokens.Colors.blockFill(entry.tint), radius: Tokens.Radius.block)
            .opacity(entry.isCompleted ? 0.55 : 1)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
        }
        .overlay(alignment: .topTrailing) {
            if entry.kind == .reminder {
                Button(action: onToggle) {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            entry.isCompleted ? .white : Tokens.Colors.card,
                            entry.isCompleted ? Tokens.Colors.hueDone : entry.tint.opacity(0.4)
                        )
                }
                .buttonStyle(.plain)
                // Rides the edge rather than sitting inside it.
                .offset(x: 10, y: 10)
            } else if entry.joinURL != nil {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(entry.tint))
                    .offset(x: 8, y: 8)
            }
        }
    }
}
