import SwiftUI
import AppKit
import DunduKit

/// Today, hour by hour, with the one button that matters on the right.
struct CalendarPage: View {
    let model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: NP.gridGap) {
            NPPageHeader(
                title: "Calendar",
                subtitle: model.agenda.isEmpty
                    ? "Nothing on today"
                    : "\(model.agenda.count) event\(model.agenda.count == 1 ? "" : "s") today"
            ) {
                NPButton(title: "Open Calendar", icon: "calendar") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
            }

            HStack(spacing: NP.gridGap) {
                agendaCard
                nextCard
            }
        }
    }

    private var agendaCard: some View {
        NPCard(padding: 11) {
            VStack(alignment: .leading, spacing: 4) {
                NPLabel("Today", icon: "calendar.day.timeline.left")
                if model.agenda.isEmpty {
                    NPEmpty(icon: "calendar", text: "A clear day.")
                } else {
                    ForEach(model.agenda.prefix(8)) { event in
                        row(event)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func row(_ event: NotchItem) -> some View {
        let past = (event.endDate ?? .distantFuture) < Date()
        let live = event.isInProgress()
        return HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(event.dueDate.map { Formatters.clockTime($0) } ?? "")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(past ? NP.C.faint : NP.C.text)
                if let end = event.endDate {
                    Text(Formatters.clockTime(end))
                        .font(NP.F.caption.monospacedDigit())
                        .foregroundStyle(NP.C.faint)
                }
            }
            .frame(width: 52, alignment: .trailing)

            // A rail rather than a bullet: it ties the two times together and
            // gives the running event somewhere to light up.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(live ? NP.C.good : (past ? NP.C.faint.opacity(0.4) : NP.C.info))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(NP.F.row)
                    .foregroundStyle(past ? NP.C.faint : NP.C.text)
                    .lineLimit(1)
                if let subtitle = event.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(NP.F.caption)
                        .foregroundStyle(NP.C.faint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if live {
                Text("NOW")
                    .font(NP.F.label)
                    .tracking(0.7)
                    .foregroundStyle(NP.C.good)
            }
            if !past, let url = event.joinURL {
                NPButton(title: "Join", icon: "video.fill", kind: live ? .primary : .secondary) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
    }

    /// A meeting already running outranks one that merely starts sooner —
    /// "up next" with a Join button is useless if it points past the call you
    /// are late for.
    private var next: NotchItem? {
        model.agenda.first { $0.isInProgress() }
            ?? model.agenda.first { ($0.endDate ?? .distantPast) > Date() }
    }

    private var nextCard: some View {
        NPCard {
            VStack(alignment: .leading, spacing: 6) {
                NPLabel("Up next", icon: "clock")
                if let next, let start = next.dueDate {
                    Text(next.isInProgress() ? "Running now" : Formatters.relativeTime(to: start))
                        .font(NP.F.value)
                        .foregroundStyle(next.isInProgress() ? NP.C.good : NP.C.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(next.title)
                        .font(NP.F.row)
                        .foregroundStyle(NP.C.dim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Formatters.clockTime(start))
                        .font(NP.F.caption.monospacedDigit())
                        .foregroundStyle(NP.C.faint)
                    if let url = next.joinURL {
                        NPButton(title: "Join meeting", icon: "video.fill", kind: .primary) {
                            NSWorkspace.shared.open(url)
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                } else {
                    NPEmpty(icon: "moon.zzz", text: "Nothing left today.")
                }
            }
        }
        .frame(width: 210)
    }
}
