// Isolated visual fixture, compiled only by Tools/DesignPreview/stage.py.
import SwiftUI
import SwiftData
import DunduKit

@main
struct DunduPreviewApp: App {
    let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: DunduStore.schema, configurations: [config])
        let context = container.mainContext
        let work = ReminderList(title: "Studio", sortOrder: 0, isDefault: true, syncEnabled: false)
        let personal = ReminderList(title: "Personal", sortOrder: 1, syncEnabled: false)
        let ideas = ReminderList(title: "Someday", sortOrder: 2, syncEnabled: false)
        [work, personal, ideas].forEach { context.insert($0) }
        let entries: [(String, String?, ReminderList, Date?)] = [
            ("Send the website proposal", "A final look at scope, then over to Maya.", work, Date().addingTimeInterval(-3600)),
            ("Gather references for the new identity", "Type, color, and a few unexpected directions.", work, nil),
            ("Review the first round of concepts", nil, work, Date().addingTimeInterval(3600)),
            ("Pick up a few things for dinner", "Tomatoes, basil, and something sweet.", personal, nil),
            ("Book a table for Saturday", nil, personal, Date().addingTimeInterval(86400)),
            ("Plan a long weekend by the coast", nil, ideas, nil)
        ]
        for (title, notes, list, due) in entries {
            let item = ReminderItem(title: title, listID: list.id)
            item.notes = notes
            item.dueDate = due
            item.hasTime = due != nil
            context.insert(item)
        }
        let review = ReminderItem(title: "Call My ah about the launch", listID: work.id, origin: .siriSuspected)
        review.suggestedTitle = "Call Maya about the launch"
        review.repairConfidence = 92
        review.reviewState = .pending
        context.insert(review)
        let routing = ReminderItem(title: "Book the photographer", listID: personal.id)
        routing.proposedTargetID = work.id.uuidString
        routing.routingReason = "This sounds like a task for Studio."
        routing.reviewState = .pending
        context.insert(routing)
        let meeting = CalendarEvent(title: "Brand direction · Maya", startAt: Date().addingTimeInterval(900), endAt: Date().addingTimeInterval(3600))
        meeting.location = "Studio catch-up"
        context.insert(meeting)
        try! context.save()
        return container
    }()
    var body: some Scene {
        WindowGroup { PreviewWorkspace().modelContainer(container) }
    }
}

struct PreviewWorkspace: View {
    @State private var selection: AppTab = .lists
    private let route = ProcessInfo.processInfo.arguments.last ?? "reminders"
    var body: some View {
        Group {
            switch route {
            case "onboarding": Color.clear.sheet(isPresented: .constant(true)) { OnboardingView() }
            case "settings": Color.clear.sheet(isPresented: .constant(true)) { SettingsView() }
            case "edit": Color.clear.sheet(isPresented: .constant(true)) { ReminderEditView(existing: nil) }
            default:
                DunduWorkspace(selection: $selection, inboxCount: 2,
                               onAdd: {}, onRecord: {}, onSettings: {})
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Colors.ground)
        .tint(Tokens.Colors.accent)
        .onAppear {
            if route == "today" { selection = .today }
            if route == "inbox" { selection = .inbox }
        }
    }
}
