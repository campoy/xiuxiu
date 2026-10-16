import SwiftUI
import SwiftData

@main
struct XiuxiuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Entry.self)
    }
}

@Model
final class Entry {
    var date: Date
    var text: String

    init(date: Date = .now, text: String) {
        self.date = date
        self.text = text
    }
}
