import Foundation
import Observation
import ServiceManagement
import OSLog

/// The system's login-item registration is the source of truth. The local
/// flag only records the one-time default setup, so switching this off in
/// Dundu or System Settings is respected on subsequent launches.
@MainActor
@Observable
final class LoginItemController {
    static let shared = LoginItemController()
    private static let setupKey = "launchAtLoginSetupCompleted"
    private let logger = Logger(subsystem: "app.scoop.dundu.mac", category: "LoginItem")

    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    var isRequested: Bool { status == .enabled || status == .requiresApproval }

    func configureDefault() {
        refresh()
        guard !UserDefaults.standard.bool(forKey: Self.setupKey) else { return }
        if status == .enabled || status == .requiresApproval {
            UserDefaults.standard.set(true, forKey: Self.setupKey)
        } else {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { UserDefaults.standard.set(true, forKey: Self.setupKey) }
        errorMessage = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Login registration failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            FileHandle.standardError.write(Data("[dundu] Login registration failed: \(error)\n".utf8))
            #endif
        }
        refresh()
        if isRequested { UserDefaults.standard.set(true, forKey: Self.setupKey) }
    }

    func refresh() {
        status = SMAppService.mainApp.status
        logger.notice("Launch at login status: \(self.status.rawValue)")
        #if DEBUG
        FileHandle.standardError.write(Data("[dundu] Launch at login status: \(status.rawValue)\n".utf8))
        #endif
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
