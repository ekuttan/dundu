import SwiftUI
import AppKit

/// Settings window: which display hosts the notch, and when peeks stay
/// quiet. Reached from the menu bar extra.
struct MacSettingsView: View {
    @AppStorage(MacPrefs.notchDisplayIDKey) private var notchDisplayID = 0
    @AppStorage(MacPrefs.peeksWhilePresentingKey) private var showWhilePresenting = false
    @AppStorage(MacPrefs.peeksDuringFocusKey) private var showDuringFocus = false

    @State private var screens: [(id: Int, name: String)] = []

    var body: some View {
        Form {
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
        .frame(width: 420)
        .fixedSize()
        .onAppear(perform: reloadScreens)
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
