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
    /// How far below the notch stays hoverable while hidden. The spec says
    /// 4pt; that is unhittably thin in practice, so the strip is deeper
    /// while still far from anything else clickable.
    static let hiddenHoverStripHeight: CGFloat = 12

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
            // Trust but verify: a nonsensical rect (transient display state
            // during wake, mode changes, or a hot-plugged screen) would put
            // the panel somewhere absurd, so fall through to the pill.
            if width > 0, frame.insetBy(dx: -1, dy: -1).contains(rect) {
                return NotchGeometry(notchRect: rect, hasHardwareNotch: true, screenFrame: frame)
            }
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

    /// The live (hoverable, clickable) region for a state, in **screen
    /// coordinates** — the same space `notchRect` and `NSEvent.mouseLocation`
    /// live in.
    ///
    /// Deliberately not in view coordinates: NSHostingView's flippedness is
    /// an implementation detail, and getting it backwards puts the hover
    /// strip 250pt below the notch, which is exactly what "reacts randomly
    /// while dragging a window, dead at the notch" looks like.
    func hoverRect(for state: NotchUIState) -> CGRect {
        switch state {
        case .hidden:
            // The notch plus a strip just under it. The cursor can't rest
            // inside the physical notch, so the reachable target is the few
            // points below it.
            return CGRect(
                x: notchRect.minX,
                y: notchRect.minY - Self.hiddenHoverStripHeight,
                width: notchRect.width,
                height: notchRect.height + Self.hiddenHoverStripHeight
            )
        case .peek:
            return CGRect(
                x: notchRect.minX - 12,
                y: notchRect.maxY - notchRect.height - Self.peekDrop,
                width: notchRect.width + 24,
                height: notchRect.height + Self.peekDrop
            )
        case .expanded:
            return panelFrame
        }
    }
}

enum NotchUIState: Equatable {
    case hidden
    case peek
    case expanded
}
