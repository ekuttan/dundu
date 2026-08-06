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
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Welcome to Dundu")
                .font(.largeTitle.bold())

            VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
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
            .padding(.horizontal, Tokens.Spacing.xl)

            Spacer()

            VStack(spacing: Tokens.Spacing.sm) {
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
                .controlSize(.large)

                Button("Not now") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.bottom, Tokens.Spacing.xl)
        }
        .interactiveDismissDisabled()
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func finish() {
        hasOnboarded = true
        dismiss()
    }
}
