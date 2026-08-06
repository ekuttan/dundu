import AppKit

/// Where the notch is on a given screen, or where the pill pretends it is.
struct NotchGeometry: Equatable {
    /// The hardware notch (or synthetic pill) rect in screen coordinates.
    var notchRect: CGRect
    var hasHardwareNotch: Bool
    var screenFrame: CGRect

    /// Panel width when expanded, per spec ~380x220.
    static let expandedSize = CGSize(width: 380, height: 220)
    /// Peek pill drops about 12pt below the notch.
    static let peekDrop: CGFloat = 26
    /// Only a 4pt strip is hit-testable while hidden.
    static let hiddenHoverStripHeight: CGFloat = 4

    static func compute(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let notchHeight = screen.safeAreaInsets.top

        if notchHeight > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // Notch width is what the menu bar strips either side leave out.
            let width = frame.width - left.width - right.width
            let rect = CGRect(
                x: frame.origin.x + left.width,
                y: frame.maxY - notchHeight,
                width: width,
                height: notchHeight
            )
            return NotchGeometry(notchRect: rect, hasHardwareNotch: true, screenFrame: frame)
        }

        // No notch: a pill of the same dimensions centred under the menu bar.
        let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        let width: CGFloat = 180
        let rect = CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - max(menuBarHeight, 24),
            width: width,
            height: max(menuBarHeight, 24)
        )
        return NotchGeometry(notchRect: rect, hasHardwareNotch: false, screenFrame: frame)
    }

    /// The panel's fixed frame: expanded-size area hanging below the notch,
    /// centred. The SwiftUI content grows and shrinks inside; hit testing is
    /// restricted to the state's visible region.
    var panelFrame: CGRect {
        let width = Self.expandedSize.width
        let height = Self.expandedSize.height + notchRect.height
        return CGRect(
            x: notchRect.midX - width / 2,
            y: notchRect.maxY - height,
            width: width,
            height: height
        )
    }

    /// Visible content rect inside the panel's coordinate space (origin at
    /// panel bottom-left, AppKit-style) for a given UI state.
    func visibleRect(for state: NotchUIState) -> CGRect {
        let panel = panelFrame
        let notchWidthInPanel = min(notchRect.width, panel.width)
        let x = (panel.width - notchWidthInPanel) / 2

        switch state {
        case .hidden:
            return CGRect(
                x: x,
                y: panel.height - notchRect.height - Self.hiddenHoverStripHeight,
                width: notchWidthInPanel,
                height: notchRect.height + Self.hiddenHoverStripHeight
            )
        case .peek:
            return CGRect(
                x: x - 12,
                y: panel.height - notchRect.height - Self.peekDrop,
                width: notchWidthInPanel + 24,
                height: notchRect.height + Self.peekDrop
            )
        case .expanded:
            return CGRect(x: 0, y: 0, width: panel.width, height: panel.height)
        }
    }
}

enum NotchUIState: Equatable {
    case hidden
    case peek
    case expanded
}
