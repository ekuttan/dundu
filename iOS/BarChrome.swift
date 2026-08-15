import SwiftUI

/// Whether the floating bar is showing everything or has pulled itself in.
///
/// Scrolling down means the user is reading, so the chrome gets out of the
/// way and leaves only the one button worth keeping within reach. Scrolling
/// back up, or settling anywhere near the top, brings it all back — the same
/// bargain the system navigation bars make.
@Observable
@MainActor
final class BarChrome {
    private(set) var isCollapsed = false

    /// Ignore anything smaller than this. Without it the bar flickers on the
    /// jitter of a finger resting on a scroll view.
    private let threshold: CGFloat = 12
    private var lastOffset: CGFloat = 0

    func report(offset: CGFloat) {
        // Near the top nothing is hidden, whatever the direction.
        guard offset < -threshold else {
            setCollapsed(false)
            lastOffset = offset
            return
        }

        let delta = offset - lastOffset
        guard abs(delta) > threshold else { return }
        setCollapsed(delta < 0)
        lastOffset = offset
    }

    private func setCollapsed(_ value: Bool) {
        guard value != isCollapsed else { return }
        withAnimation(Tokens.Anim.chrome) { isCollapsed = value }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Put this on the scroll view. It names a coordinate space and listens
    /// for the probe's position inside it.
    func tracksScroll(_ chrome: BarChrome?) -> some View {
        coordinateSpace(name: ScrollProbe.space)
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                Task { @MainActor in chrome?.report(offset: offset) }
            }
    }
}

/// Sits as the first row inside the scroll content and reports where it is.
/// iOS 18 has `onScrollGeometryChange` for this; the deployment target is 17,
/// so a probe it is.
struct ScrollProbe: View {
    static let space = "dundu-scroll"

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollOffsetKey.self,
                value: geo.frame(in: .named(Self.space)).minY
            )
        }
        .frame(height: 0)
    }
}
