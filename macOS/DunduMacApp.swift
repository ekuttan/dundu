import SwiftUI
import SwiftData
import DunduKit

/// One container for the whole process — the menu bar extra, the notch
/// panel, and the app delegate all share it.
@MainActor
enum MacStores {
    static let container: ModelContainer = {
        do {
            return try DunduStore.container()
        } catch {
            fatalError("Failed to open the Dundu store: \(error)")
        }
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let controller = NotchPanelController(container: MacStores.container)
            NotchPanel.shared = controller
            controller.start()
        }
    }
}

/// Agent app: LSUIElement is set in the target's Info.plist keys, so there is
/// no Dock icon and no main window at launch. The menu bar extra is the only
/// always-visible surface; the notch panel appears on its own schedule.
@main
struct DunduMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let container = MacStores.container

    var body: some Scene {
        MenuBarExtra("Dundu", systemImage: "circle.grid.2x1.left.filled") {
            MenuBarView()
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
        }
    }
}
