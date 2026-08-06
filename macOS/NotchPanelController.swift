import AppKit
import SwiftUI
import SwiftData
import DunduKit

/// Owns the notch NSPanel: geometry, hover timing, state transitions, and
/// hit-testing. The panel is a fixed expanded-size transparent window below
/// the notch; SwiftUI animates the visible content inside it, and hit
/// testing is clipped to the current state's visible region so clicks fall
/// through everywhere else.
@MainActor
final class NotchPanelController {
    private let container: ModelContainer
    let model = NotchModel()

    private var panel: NotchNSPanel?
    private var hostingView: PassthroughHostingView<NotchView>?
    private var geometry: NotchGeometry?

    private var expandTimer: Timer?
    private var collapseTimer: Timer?
    private let scheduler = NotchScheduler()
    /// Undo windows for completions made in the notch, keyed by item.
    private var undoTimers: [UUID: Timer] = [:]

    /// Completing from the notch commits after this window, per spec.
    static let undoWindow: TimeInterval = 3

    /// Due items the user has already seen (expanded the panel over them).
    /// The peek raises only for items outside this set, so it appears at the
    /// moment something new becomes due — never "randomly" after an
    /// unrelated sync while an old overdue backlog exists.
    private var acknowledgedDueIDs: Set<UUID> = []

    /// Hover timing per spec: 120ms before expanding so a cursor passing
    /// through to the menu bar doesn't trigger it, 400ms before collapsing so
    /// a wobble doesn't close it mid-interaction.
    static let expandDelay: TimeInterval = 0.12
    static let collapseDelay: TimeInterval = 0.4

    init(container: ModelContainer) {
        self.container = container

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                NotchPanel.shared?.rebuildPanel()
            }
        }
    }

    // MARK: - Setup

    func start() {
        rebuildPanel()
        scheduler.onFire = { [weak self] in self?.refresh() }
        PeekSuppression.requestFocusAuthorizationIfNeeded()
        refresh()
    }

    /// The chosen display, defaulting to the built-in notch display.
    static func targetScreen() -> NSScreen? {
        let preferred = MacPrefs.notchDisplayID
        if preferred != 0 {
            for screen in NSScreen.screens {
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                if number?.uint32Value == preferred {
                    return screen
                }
            }
        }
        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private var currentScreen: NSScreen?

    func rebuildPanel() {
        panel?.orderOut(nil)
        panel = nil

        guard let screen = Self.targetScreen() else { return }
        currentScreen = screen
        let geometry = NotchGeometry.compute(for: screen)
        self.geometry = geometry

        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let view = NotchView(
            model: model,
            geometry: geometry,
            onComplete: { [weak self] item in self?.complete(item) },
            onUndo: { [weak self] item in self?.undo(item) },
            onSnooze: { [weak self] item, option in self?.snooze(item, option: option) },
            onQuickAdd: { [weak self] title in self?.addQuickReminder(title) },
            onQuickAddFocus: { [weak self] active in self?.setQuickAddActive(active) },
            onOpenSettings: { Self.openSettings() }
        )

        let hosting = PassthroughHostingView(rootView: view)
        hosting.visibleRectProvider = { [weak self] in
            guard let self, let geometry = self.geometry else { return .zero }
            return geometry.visibleRect(for: self.model.uiState)
        }
        hosting.onHoverChange = { [weak self] hovering in
            self?.hoverChanged(hovering)
        }
        self.hostingView = hosting

        let panel = NotchNSPanel(
            contentRect: geometry.panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Order matters: isFloatingPanel resets level, so level comes after.
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        panel.setFrame(geometry.panelFrame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    // MARK: - Content

    func refresh() {
        let context = ModelContext(container)
        model.refresh(context: context)
        scheduler.rearm(for: model.nextFire?.date)

        // Suppression stops Dundu volunteering a peek while the user is
        // presenting, sharing, or in a Focus. Hover still works, and an
        // already-expanded panel is never yanked away mid-interaction.
        let suppressed = PeekSuppression.evaluate(on: currentScreen).suppressed

        // Completed and snoozed items leave the acknowledged set with the
        // due set; a returning snooze counts as newly due again.
        let dueIDs = Set(model.items.map(\.id))
        acknowledgedDueIDs.formIntersection(dueIDs)
        let hasNewDue = !dueIDs.subtracting(acknowledgedDueIDs).isEmpty

        switch model.uiState {
        case .hidden where hasNewDue && !suppressed:
            model.uiState = .peek
        case .peek where !model.hasContent || suppressed:
            model.uiState = .hidden
        case .expanded where !model.hasContent && undoTimers.isEmpty && !isHovering:
            model.uiState = .hidden
        default:
            break
        }
    }

    /// Expanding over due items counts as seeing them (spec: the peek stays
    /// until completed, snoozed, or dismissed — this is the dismissal).
    private func acknowledgeVisibleDueItems() {
        acknowledgedDueIDs.formUnion(model.items.map(\.id))
    }

    // MARK: - Hover

    private var isHovering = false

    private func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            collapseTimer?.invalidate()
            collapseTimer = nil
            // Hover expands any time — the notch answers "what's next" on
            // demand, not only when something is already due.
            guard model.uiState != .expanded else { return }
            guard expandTimer == nil else { return }
            expandTimer = Timer.scheduledTimer(withTimeInterval: Self.expandDelay, repeats: false) { _ in
                Task { @MainActor in
                    guard let self = NotchPanel.shared else { return }
                    self.expandTimer = nil
                    if self.isHovering {
                        self.model.uiState = .expanded
                    }
                }
            }
        } else {
            expandTimer?.invalidate()
            expandTimer = nil
            guard model.uiState == .expanded, collapseTimer == nil else { return }
            collapseTimer = Timer.scheduledTimer(withTimeInterval: Self.collapseDelay, repeats: false) { _ in
                Task { @MainActor in
                    guard let self = NotchPanel.shared else { return }
                    self.collapseTimer = nil
                    // The user expanded and left: they have seen the due
                    // items, so retract fully instead of re-peeking.
                    self.acknowledgeVisibleDueItems()
                    self.model.uiState = .hidden
                }
            }
        }
    }

    // MARK: - Actions

    /// Checkbox completes with a 3-second undo window: the row shows as done
    /// immediately, the store write and sync happen only when the window
    /// closes without an undo.
    private func complete(_ item: NotchItem) {
        guard undoTimers[item.id] == nil else { return }
        model.pendingUndo.insert(item.id)

        undoTimers[item.id] = Timer.scheduledTimer(
            withTimeInterval: Self.undoWindow, repeats: false
        ) { _ in
            Task { @MainActor in
                NotchPanel.shared?.commitCompletion(item)
            }
        }
    }

    private func undo(_ item: NotchItem) {
        undoTimers.removeValue(forKey: item.id)?.invalidate()
        model.pendingUndo.remove(item.id)
    }

    fileprivate func commitCompletion(_ item: NotchItem) {
        undoTimers.removeValue(forKey: item.id)?.invalidate()
        model.pendingUndo.remove(item.id)

        let context = ModelContext(container)
        if let target = try? context.fetch(FetchDescriptor<ReminderItem>()).first(where: { $0.id == item.id }) {
            context.setCompleted(target, true)
            try? context.save()
            Task { await ReminderSyncService.syncNow(context: ModelContext(container)) }
        }
        refresh()
    }

    /// Quick add straight from the notch — the menu bar shortcut the panel
    /// was missing.
    private func addQuickReminder(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let context = ModelContext(container)
        if let list = try? context.defaultList() {
            let item = ReminderItem(title: trimmed, listID: list.id)
            context.insert(item)
            try? context.save()
            Task { await ReminderSyncService.syncNow(context: ModelContext(container)) }
        }
        refresh()
    }

    /// The panel is nonactivating so hover never steals focus; typing in the
    /// quick-add field needs key status, granted only while the field is
    /// active and returned the moment it isn't.
    private func setQuickAddActive(_ active: Bool) {
        panel?.allowsKey = active
        if active {
            panel?.makeKey()
        } else {
            panel?.resignKey()
        }
    }

    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func snooze(_ item: NotchItem, option: SnoozeOption) {
        let context = ModelContext(container)
        if let target = try? context.fetch(FetchDescriptor<ReminderItem>()).first(where: { $0.id == item.id }) {
            target.dueDate = option.resolve()
            target.modifiedAt = Date()
            try? context.save()
            Task { await ReminderSyncService.syncNow(context: ModelContext(container)) }
        }
        refresh()
    }
}

/// Global access point so timers and notifications reach the controller
/// without retain cycles.
@MainActor
enum NotchPanel {
    static var shared: NotchPanelController?
}

/// AppKit constrains windows below the menu bar by default; the notch panel
/// must hug the physical top of the screen, so the constraint is disabled.
final class NotchNSPanel: NSPanel {
    /// Key status is granted only while the quick-add field is active, so
    /// plain hovering never steals focus from whatever the user is typing in.
    var allowsKey = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

// MARK: - Passthrough hosting view

/// Hosting view that limits hit testing to the visible region and reports
/// hover transitions against it. Tracking uses `.activeAlways` — the
/// nonactivating panel makes hover work without the app being frontmost.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var visibleRectProvider: (() -> CGRect)?
    var onHoverChange: ((Bool) -> Void)?

    private var isInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let rect = visibleRectProvider?(), rect.contains(convert(point, from: superview)) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setInside(false)
    }

    private func updateHover(with event: NSEvent) {
        guard let rect = visibleRectProvider?() else { return }
        let point = convert(event.locationInWindow, from: nil)
        setInside(rect.contains(point))
    }

    private func setInside(_ inside: Bool) {
        guard inside != isInside else { return }
        isInside = inside
        onHoverChange?(inside)
    }
}
