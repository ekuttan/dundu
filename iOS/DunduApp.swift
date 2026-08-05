import SwiftUI
import SwiftData
import DunduKit

@main
struct DunduApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try DunduStore.container()
        } catch {
            fatalError("Failed to open the Dundu store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
