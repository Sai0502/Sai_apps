import SwiftUI
import SwiftData

@main
struct WorkoutToDoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [ProjectItem.self, SetItem.self, CheckItem.self, GapItem.self])
    }
}
