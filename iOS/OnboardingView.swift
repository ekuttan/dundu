import SwiftUI
import DunduKit

/// First launch: what Dundu is, then the Reminders access ask. Denial is a
/// fine outcome — the app works standalone and says so.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxl) {
                VStack(spacing: Tokens.Spacing.lg) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Tokens.Colors.accent)
                    Text("Welcome to Dundu")
                        .font(Tokens.Typo.largeTitle)
                        .multilineTextAlignment(.center)
                    Text("Reminders and calendars, together.")
                        .font(Tokens.Typo.body)
                        .foregroundStyle(Tokens.Colors.quiet)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.Spacing.xxl)

                VStack(spacing: Tokens.Spacing.md) {
                    featureRow(icon: "checklist", title: "Stay in sync",
                               detail: "Reminders sync both ways with Apple. Connect Google Calendar for your meetings.")
                    featureRow(icon: "macwindow", title: "Available on Mac",
                               detail: "On your Mac, due reminders and upcoming meetings appear beneath the notch.")
                    featureRow(icon: "sparkles", title: "Private intelligence",
                               detail: "On-device intelligence suggests the right list and catches dictation mistakes.")
                }

                VStack(spacing: Tokens.Spacing.md) {
                    Button {
                        Task {
                            _ = try? await ReminderSyncService.bridge.requestFullAccess()
                            finish()
                        }
                    } label: {
                        Text("Connect Apple Reminders")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    Button("Start without connecting") { finish() }
                        .font(Tokens.Typo.label)
                        .buttonStyle(.plain)
                        .foregroundStyle(Tokens.Colors.quiet)
                        .frame(minHeight: Tokens.Layout.control)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Tokens.Layout.gutter)
            .padding(.bottom, Tokens.Spacing.xxl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Tokens.Colors.ground)
        .interactiveDismissDisabled()
    }

    /// A simple feature row, without its own surface.
    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.accent)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(title)
                        .font(Tokens.Typo.cardTitle)
                        .foregroundStyle(Tokens.Colors.ink)
                    Text(detail)
                        .font(Tokens.Typo.label)
                        .foregroundStyle(Tokens.Colors.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, Tokens.Spacing.md)
    }

    private func finish() {
        hasOnboarded = true
        dismiss()
    }
}
