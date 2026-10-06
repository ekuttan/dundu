import SwiftUI
import AppKit

/// Pomodoro, countdowns, stopwatch and hydration — four cards across, each
/// one self-contained so the page never needs scrolling.
struct FocusPage: View {
    @Bindable var focus: FocusModel

    private static let presets: [(label: String, minutes: Int)] = [
        ("Coffee", 5), ("Break", 10), ("Sprint", 25),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: NP.gridGap) {
            NPPageHeader(title: "Focus") {
                Text("Pomodoro, countdowns & hydration")
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.faint)
            }

            // Fixed rather than filling: four small instruments stretched
            // over 380pt leaves every control floating in its own void.
            HStack(spacing: NP.gridGap) {
                pomodoroCard
                countdownCard
                stopwatchCard
                hydrationCard
            }
            .frame(height: 270)

            Spacer(minLength: 0)
        }
    }

    private var pomodoroCard: some View {
        NPCard {
            VStack(spacing: 6) {
                NPLabel("Pomodoro")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.001, min(1, focus.pomodoroFraction)))
                        .stroke(
                            focus.pomodoro.isBreak ? NP.C.info : NP.C.good,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text(focus.pomodoroClock)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NP.C.text)
                }
                .frame(width: 74, height: 74)

                Text(focus.pomodoro.isBreak ? "Break" : "Sprint")
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.dim)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    NPButton(
                        title: focus.pomodoro.isRunning ? "Pause" : "Start",
                        kind: .primary
                    ) { focus.togglePomodoro() }
                    Button { focus.resetPomodoro() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NP.C.dim)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color(white: 0.16)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var countdownCard: some View {
        NPCard {
            VStack(alignment: .leading, spacing: 6) {
                NPLabel("Countdown")

                if let running = focus.countdown, let clock = focus.countdownClock {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clock)
                            .font(NP.F.value)
                            .foregroundStyle(NP.C.text)
                        Text(running.label)
                            .font(NP.F.caption)
                            .foregroundStyle(NP.C.faint)
                        NPButton(title: "Cancel") { focus.cancelCountdown() }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    ForEach(Self.presets, id: \.label) { preset in
                        Button {
                            focus.startCountdown(label: preset.label, minutes: preset.minutes)
                        } label: {
                            HStack {
                                Text("\(preset.minutes)m \(preset.label)")
                                    .font(NP.F.row)
                                    .foregroundStyle(NP.C.text)
                                Spacer()
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(NP.C.faint)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: NP.R.chip, style: .continuous)
                                    .fill(Color(white: 0.14))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)

                    NPButton(title: "Open Apple Clock", icon: "clock") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Clock.app"))
                    }
                }
            }
        }
    }

    private var stopwatchCard: some View {
        NPCard {
            VStack(spacing: 8) {
                NPLabel("Stopwatch")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Text(focus.stopwatchClock)
                    .font(.system(size: 24, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NP.C.text)
                HStack(spacing: 6) {
                    NPButton(
                        title: focus.stopwatchRunning ? "Stop" : "Start",
                        kind: .primary
                    ) { focus.toggleStopwatch() }
                    NPButton(title: "Reset") { focus.resetStopwatch() }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var hydrationCard: some View {
        NPCard {
            VStack(spacing: 5) {
                NPLabel("Hydration")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Image(systemName: "drop.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(NP.C.info)
                Text(focus.hydrationLabel)
                    .font(NP.F.valueSmall)
                    .foregroundStyle(NP.C.text)
                Text("Every \(Int(focus.hydrationEvery / 60))m nudge")
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.faint)
                NPButton(title: "Drink", icon: "cup.and.saucer") { focus.drink() }
                if focus.glasses > 0 {
                    Text("\(focus.glasses) today")
                        .font(NP.F.caption)
                        .foregroundStyle(NP.C.faint)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
