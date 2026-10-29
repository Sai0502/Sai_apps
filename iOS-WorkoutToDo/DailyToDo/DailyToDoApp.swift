import SwiftUI
import SwiftData

@main
struct DailyToDoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [ProjectItem.self, SetItem.self, CheckItem.self])
    }
}
