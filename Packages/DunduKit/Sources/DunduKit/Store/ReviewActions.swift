import Foundation
import SwiftData

/// Accept/dismiss for Inbox questions. One implementation shared by the
/// iOS cards, the notification action buttons, and (later) the Mac window,
/// so a decision means the same thing everywhere.
extension ModelContext {
    /// "Use suggested title." Applies the repair and stamps the item dirty
    /// so the fix reaches Apple Reminders on the next pass.
    public func acceptRepair(_ item: ReminderItem, at date: Date = Date()) {
        guard let suggested = item.suggestedTitle else { return }
        item.title = suggested
        item.suggestedTitle = nil
        item.repairConfidence = nil
        item.modifiedAt = date
        settleReviewState(item, resolved: true)
    }

    /// "Keep original." The suggestion is dropped, never re-asked — a wrong
    /// auto-correction erodes trust, and so does nagging.
    public func rejectRepair(_ item: ReminderItem) {
        item.suggestedTitle = nil
        item.repairConfidence = nil
        settleReviewState(item, resolved: false)
    }

    /// "Move it there." Applies the proposed routing target.
    public func acceptRouting(_ item: ReminderItem, at date: Date = Date()) {
        if let proposed = item.proposedTargetID, let listID = UUID(uuidString: proposed) {
            item.listID = listID
            item.modifiedAt = date
        }
        item.proposedTargetID = nil
        settleReviewState(item, resolved: true)
    }

    /// "Leave it where it is."
    public func rejectRouting(_ item: ReminderItem) {
        item.proposedTargetID = nil
        settleReviewState(item, resolved: false)
    }

    /// Dismisses everything pending on the item in one go (swipe-away).
    public func dismissAllReviews(_ item: ReminderItem) {
        item.suggestedTitle = nil
        item.repairConfidence = nil
        item.proposedTargetID = nil
        item.reviewState = .dismissed
    }

    private func settleReviewState(_ item: ReminderItem, resolved: Bool) {
        // The card stays pending while the other question is still open.
        if item.suggestedTitle == nil && item.proposedTargetID == nil {
            item.reviewState = resolved ? .resolved : .dismissed
        }
    }
}

extension ReminderItem {
    /// Whether this item currently has an open Inbox question.
    public var needsReview: Bool {
        reviewState == .pending && (suggestedTitle != nil || proposedTargetID != nil || routingConfidence.map { $0 < 50 } == true)
    }
}
