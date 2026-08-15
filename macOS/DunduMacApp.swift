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
    /// Resyncs when the Mac wakes or Dundu is brought forward. Sleep stops
    /// timers and can swallow EventKit change notifications outright, so
    /// neither can be relied on to catch us up on its own.
    @MainActor
    private func observeWake(controller: NotchPanelController) {
        let resync = {
            Task { @MainActor in
                await ReminderSyncService.syncNow(context: ModelContext(MacStores.container))
                await GoogleSyncService.syncNow(context: ModelContext(MacStores.container))
                controller.refresh()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in resync() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in resync() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let controller = NotchPanelController(container: MacStores.container)
            NotchPanel.shared = controller
            controller.start()

            // Ask at launch, not on first menu-bar open — the dialog should
            // greet the user, not hide until they find the icon.
            if EventKitBridge.accessStatus() == .notDetermined {
                _ = try? await ReminderSyncService.bridge.requestFullAccess()
            }
            await ReminderSyncService.syncNow(context: ModelContext(MacStores.container))
            await GoogleSyncService.syncNow(context: ModelContext(MacStores.container))
            controller.refresh()

            // A menu bar app runs for days. Waking the Mac, or simply time
            // passing, has to bring it back in step — a seven-hour-old
            // process showing seven-hour-old reminders is the failure this
            // prevents.
            observeWake(controller: controller)

            // Google has no push without a webhook: poll every 5 minutes
            // while running (spec §7). Reminders ride the same tick: EKEvent
            // change notifications can be missed across sleep.
            while true {
                try? await Task.sleep(for: GoogleSyncService.pollInterval)
                await ReminderSyncService.syncNow(context: ModelContext(MacStores.container))
                await GoogleSyncService.syncNow(context: ModelContext(MacStores.container))
                controller.refresh()
            }
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
