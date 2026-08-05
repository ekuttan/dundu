import SwiftUI

/// Design tokens shared by every surface. Kept out of DunduKit on purpose —
/// DunduKit never knows which platform it runs on, and views never define
/// their own magic numbers.
enum Tokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 12
        static let pill: CGFloat = 22
    }

    enum Anim {
        /// Notch spring per spec: ~0.35s response, 0.7 damping.
        static let notchSpring = Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let reduceMotionFallback = Animation.easeInOut(duration: 0.15)
    }

    enum Colors {
        static let overdue = Color.red
        static let dueSoon = Color.orange
        static let meeting = Color.blue
    }
}
