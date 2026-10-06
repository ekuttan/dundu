import SwiftUI

/// The pages the expanded panel can show, in dock order.
enum NotchPage: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case tasks
    case calendar
    case coding
    case focus
    case inbox

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .focus: "timer"
        case .inbox: "tray"
        }
    }

    var title: String {
        switch self {
        case .dashboard: "Overview"
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        case .coding: "Coding"
        case .focus: "Focus"
        case .inbox: "Inbox"
        }
    }
}

/// The floating dock under the panel: pages on the left of the divider,
/// app-level controls on the right as their own round buttons.
///
/// It is a separate shape from the panel on purpose. The panel is the thing
/// you read; the dock is the thing you aim at, and keeping it detached means
/// it can stay the same size whatever page is open.
struct NotchDock: View {
    @Binding var page: NotchPage
    let badges: [NotchPage: Int]
    let isPinned: Bool
    let onPin: () -> Void
    let onSettings: () -> Void

    static let height: CGFloat = 46
    /// Gap between the panel's bottom edge and the dock.
    static let gap: CGFloat = 10

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(NotchPage.allCases) { item in
                    DockButton(
                        icon: item.icon,
                        isOn: page == item,
                        badge: badges[item] ?? 0,
                        help: item.title
                    ) {
                        page = item
                    }
                }
            }
            .padding(5)
            .background(Capsule().fill(Color.black.opacity(0.92)))
            .overlay(Capsule().strokeBorder(NP.C.stroke))

            RoundButton(icon: "gearshape", isOn: false, help: "Dundu settings", action: onSettings)
            RoundButton(
                icon: "pin.fill",
                isOn: isPinned,
                help: isPinned ? "Unpin the panel" : "Keep the panel open",
                action: onPin
            )
        }
        .frame(height: Self.height)
    }
}

private struct DockButton: View {
    let icon: String
    let isOn: Bool
    let badge: Int
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isOn ? Color(white: 0.2) : (hovering ? Color(white: 0.13) : .clear))
                    .frame(width: 38, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? NP.C.text : NP.C.dim)
                    .frame(width: 38, height: 34)
                if badge > 0 {
                    Circle()
                        .fill(NP.C.bad)
                        .frame(width: 6, height: 6)
                        .offset(x: -6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct RoundButton: View {
    let icon: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isOn ? Color(white: 0.96) : Color.black.opacity(0.92))
                    .overlay(Circle().strokeBorder(NP.C.stroke))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? .black : (hovering ? NP.C.text : NP.C.dim))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
