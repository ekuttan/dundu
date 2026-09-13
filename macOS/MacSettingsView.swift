import SwiftUI
import AppKit

/// Settings window: which display hosts the notch, and when peeks stay
/// quiet. Reached from the menu bar extra.
struct MacSettingsView: View {
    @AppStorage(MacPrefs.notchDisplayIDKey) private var notchDisplayID = 0
    @AppStorage(MacPrefs.peeksWhilePresentingKey) private var showWhilePresenting = false
    @AppStorage(MacPrefs.peeksDuringFocusKey) private var showDuringFocus = false

    @State private var loginItem = LoginItemController.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var screens: [(id: Int, name: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text("Settings")
                    .font(.title2.bold())
                    .foregroundStyle(Tokens.Colors.ink)
                Text("General, display and notifications")
                    .font(Tokens.Typo.label)
                    .foregroundStyle(Tokens.Colors.quiet)
            }
            .padding(Tokens.Spacing.xl)
            Form {
                Section {
                    Toggle("Open Dundu at login", isOn: Binding(
                        get: { loginItem.isRequested },
                        set: { loginItem.setEnabled($0) }
                    ))
                    if loginItem.status == .requiresApproval {
                        Text("Allow Dundu in System Settings to finish enabling automatic launch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items", action: loginItem.openSystemSettings)
                    }
                    if let error = loginItem.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("General")
                } footer: {
                    Text("Starts quietly in the menu bar when you sign in to your Mac.")
                }

                Section("Notch display") {
                    Picker("Show the panel on", selection: $notchDisplayID) {
                        Text("Automatic (built-in first)").tag(0)
                        ForEach(screens, id: \.id) { screen in
                            Text(screen.name).tag(screen.id)
                        }
                    }
                    .onChange(of: notchDisplayID) {
                        NotchPanel.shared?.rebuildPanel()
                        NotchPanel.shared?.refresh()
                    }
                }

                Section {
                    Toggle("Show peeks while presenting or sharing the screen", isOn: $showWhilePresenting)
                    Toggle("Show peeks during Focus", isOn: $showDuringFocus)
                } header: {
                    Text("Quiet times")
                } footer: {
                    Text("Off means Dundu stays hidden in those moments. Hovering the notch always works.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .tint(Tokens.Colors.accent)
        .background(Tokens.Colors.ground)
        .frame(width: 480)
        .fixedSize()
        .onAppear {
            reloadScreens()
            loginItem.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loginItem.refresh() }
        }
    }

    private func reloadScreens() {
        screens = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            return (id: Int(number.uint32Value), name: screen.localizedName)
        }
    }
}
