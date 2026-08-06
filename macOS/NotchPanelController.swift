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

    private var panel: NSPanel?
    private var hostingView: PassthroughHostingView<NotchView>?
    private var geometry: NotchGeometry?

    private var expandTimer: Timer?
    private var collapseTimer: Timer?
    private var refreshTimer: Timer?

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
        refresh()

        // M5 replaces this with the real due-date scheduler; until then a
        // coarse timer keeps the panel honest.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                NotchPanel.shared?.refresh()
            }
        }
    }

    func rebuildPanel() {
        panel?.orderOut(nil)
        panel = nil

        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            return
        }
        let geometry = NotchGeometry.compute(for: screen)
        self.geometry = geometry

        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let view = NotchView(
            model: model,
            geometry: geometry,
            onComplete: { [weak self] item in self?.complete(item) },
            onSnooze: { [weak self] item, option in self?.snooze(item, option: option) }
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

        // A due item raises the peek; an emptied list retracts everything
        // unless the user is mid-interaction in the expanded panel.
        switch model.uiState {
        case .hidden where model.hasContent:
            model.uiState = .peek
        case .peek where !model.hasContent:
            model.uiState = .hidden
        case .expanded where !model.hasContent:
            model.uiState = .hidden
        default:
            break
        }
    }

    // MARK: - Hover

    private func hoverChanged(_ hovering: Bool) {
        if hovering {
            collapseTimer?.invalidate()
            collapseTimer = nil
            guard model.uiState != .expanded, model.hasContent else { return }
            guard expandTimer == nil else { return }
            expandTimer = Timer.scheduledTimer(withTimeInterval: Self.expandDelay, repeats: false) { _ in
                Task { @MainActor in
                    guard let self = NotchPanel.shared else { return }
                    self.expandTimer = nil
                    if self.model.hasContent {
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
                    self.model.uiState = self.model.hasContent ? .peek : .hidden
                }
            }
        }
    }

    // MARK: - Actions

    private func complete(_ item: NotchItem) {
        let context = ModelContext(container)
        if let target = try? context.fetch(FetchDescriptor<ReminderItem>()).first(where: { $0.id == item.id }) {
            context.setCompleted(target, true)
            try? context.save()
            Task { await ReminderSyncService.syncNow(context: ModelContext(container)) }
        }
        refresh()
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
private final class NotchNSPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
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
