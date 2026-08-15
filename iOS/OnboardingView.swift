import SwiftUI
import DunduKit

/// First launch: what Dundu is, then the Reminders access ask. Denial is a
/// fine outcome — the app works standalone and says so.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            Spacer()

            Image(systemName: "circle.grid.2x1.left.filled")
                .font(.system(size: 52))
                .foregroundStyle(Tokens.Colors.accentGradient)

            Text("Welcome to Dundu")
                .font(Tokens.Typo.largeTitle)
                .foregroundStyle(Tokens.Colors.ink)

            VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                featureRow(
                    icon: "checklist",
                    title: "One place for reminders",
                    detail: "Two-way sync with Apple Reminders. Everything you add here lands there, and back."
                )
                featureRow(
                    icon: "macwindow",
                    title: "Lives in the Mac notch",
                    detail: "Due items and meetings appear under the notch, then get out of the way."
                )
                featureRow(
                    icon: "brain",
                    title: "On-device intelligence",
                    detail: "Routing and Siri-typo fixes run on your device. Nothing leaves it."
                )
            }
            .padding(.horizontal, Tokens.Layout.gutter)

            Spacer()

            VStack(spacing: Tokens.Spacing.md) {
                PillButton(title: "Connect Apple Reminders", style: .accent) {
                    Task {
                        _ = try? await ReminderSyncService.bridge.requestFullAccess()
                        finish()
                    }
                }

                Button("Not now") { finish() }
                    .font(Tokens.Typo.body)
                    .buttonStyle(.plain)
                    .foregroundStyle(Tokens.Colors.quiet)
            }
            .padding(.horizontal, Tokens.Layout.gutter)
            .padding(.bottom, Tokens.Spacing.xxl)
        }
        .background(Tokens.Colors.ground)
        .interactiveDismissDisabled()
    }

    /// One promise per card, so the three read as a list of things the app
    /// does rather than a wall of paragraphs.
    private func featureRow(icon: String, title: String, detail: String) -> some View {
        SoftCard {
            HStack(alignment: .top, spacing: Tokens.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.accent)
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Tokens.Colors.blockFill(Tokens.Colors.accent))
                    }
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
        }
    }

    private func finish() {
        hasOnboarded = true
        dismiss()
    }
}
