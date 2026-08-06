import SwiftUI
import SwiftData
import DunduKit

/// Google accounts and their calendars. Multi-account from the start —
/// three calendars may live on three addresses. Roles are what the AI
/// routes against; titles change, roles don't.
struct GoogleAccountsView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [CalendarAccount]
    @Query private var calendarRefs: [CalendarRef]

    @State private var isSigningIn = false
    @State private var signInError: String?

    private var googleAccounts: [CalendarAccount] {
        accounts.filter { $0.provider == .google }
    }

    var body: some View {
        List {
            if let signInError {
                Section {
                    Label(signInError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(googleAccounts) { account in
                Section {
                    ForEach(calendars(for: account)) { calendar in
                        CalendarRefRow(calendar: calendar) {
                            try? context.save()
                        }
                    }
                } header: {
                    Text(account.email)
                } footer: {
                    Button("Remove this account", role: .destructive) {
                        try? GoogleAccountService.shared.removeAccount(account, context: context)
                    }
                    .font(.caption)
                }
            }

            Section {
                Button {
                    signIn()
                } label: {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Label(
                            googleAccounts.isEmpty ? "Add Google Account" : "Add another account",
                            systemImage: "plus"
                        )
                    }
                }
                .disabled(isSigningIn)
            } footer: {
                Text("Sign-in happens on google.com; Dundu only ever holds the resulting token, in the Keychain. In testing mode Google expires sessions every 7 days.")
            }
        }
        .navigationTitle("Google Calendar")
    }

    private func calendars(for account: CalendarAccount) -> [CalendarRef] {
        calendarRefs
            .filter { $0.accountID == account.id }
            .sorted { ($0.isDefaultForRole ? 0 : 1, $0.title) < ($1.isDefaultForRole ? 0 : 1, $1.title) }
    }

    private func signIn() {
        isSigningIn = true
        signInError = nil
        Task {
            defer { isSigningIn = false }
            do {
                try await GoogleAccountService.shared.signIn(context: context)
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}

private struct CalendarRefRow: View {
    @Bindable var calendar: CalendarRef
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            HStack {
                Circle()
                    .fill(Color(hex: calendar.colorHex) ?? .green)
                    .frame(width: 10, height: 10)
                Text(calendar.title)
                    .lineLimit(1)
                Spacer()
                Toggle("Sync", isOn: Binding(
                    get: { calendar.syncEnabled },
                    set: { calendar.syncEnabled = $0; onChange() }
                ))
                .labelsHidden()
            }
            if calendar.syncEnabled {
                Picker("Role", selection: Binding(
                    get: { calendar.role },
                    set: { calendar.role = $0; onChange() }
                )) {
                    Text("Personal").tag(CalendarRef.Role.personal)
                    Text("Work A").tag(CalendarRef.Role.workA)
                    Text("Work B").tag(CalendarRef.Role.workB)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
        }
    }
}
