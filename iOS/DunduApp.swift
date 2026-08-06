import SwiftUI
import SwiftData
import UserNotifications
import DunduKit

/// One container for the whole process — views, notification actions, and
/// background handlers all share it.
@MainActor
enum IOSStores {
    static let container: ModelContainer = {
        do {
            return try DunduStore.container()
        } catch {
            fatalError("Failed to open the Dundu store: \(error)")
        }
    }()
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            InboxNotifier.registerCategories()
        }
        return true
    }

    /// Notification action buttons resolve the question without opening the
    /// app; "Open" and plain taps land in the Inbox.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        let itemID = response.notification.request.content.userInfo["itemID"] as? String

        guard let itemID,
              identifier == InboxNotifier.useSuggestedAction
                || identifier == InboxNotifier.keepOriginalAction
        else { return }

        await InboxNotifier.handleAction(
            identifier: identifier,
            itemID: itemID,
            container: IOSStores.container
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct DunduApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let container = IOSStores.container

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
