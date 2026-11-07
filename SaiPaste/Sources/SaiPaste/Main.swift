import AppKit

@main
struct SaiPasteMain {
    static func main() {
        // Two copies of the app share one store.json and the last one to save wins,
        // which silently drops history. Keep a single instance alive instead.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            if let running = others.first {
                BarLog.log.log("second instance refused: pid=\(running.processIdentifier, privacy: .public)")
                _ = running.activate(options: [])
                exit(0)
            }
        }

        let app = NSApplication.shared
        let delegate = AppController.shared
        app.delegate = delegate
        app.run()
    }
}
