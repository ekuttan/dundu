import SwiftUI
import SwiftData
import DunduKit

/// Agent app: LSUIElement is set in the target's Info.plist keys, so there is
/// no Dock icon and no main window at launch. The menu bar extra is the only
/// always-visible surface; the notch panel (M4) appears on its own schedule.
@main
struct DunduMacApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try DunduStore.container()
        } catch {
            fatalError("Failed to open the Dundu store: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra("Dundu", systemImage: "circle.grid.2x1.left.filled") {
            MenuBarView()
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
    }
}
