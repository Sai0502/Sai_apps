import AppKit
import Foundation

final class ZoneLogger {
    static let shared = ZoneLogger()

    private let maxLines = 300
    private let formatter = ISO8601DateFormatter()
    private let logFileURL: URL
    private let logDirectoryURL: URL
    private var recentLines: [String] = []

    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logDirectoryURL = baseDirectory.appendingPathComponent("FitRecordZone", isDirectory: true)
        logFileURL = logDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        if let contents = try? String(contentsOf: logFileURL) {
            recentLines = contents.split(separator: "\n").map(String.init).suffix(maxLines)
        }
    }

    func log(_ event: String, details: [String: String] = [:]) {
        let time = formatter.string(from: Date())
        var segments = ["[\(time)]", event]
        if !details.isEmpty {
            let body = details.keys.sorted().map { "\($0)=\(details[$0] ?? "")" }.joined(separator: " ")
            segments.append(body)
        }
        let line = segments.joined(separator: " | ")
        recentLines.append(line)
        if recentLines.count > maxLines {
            recentLines.removeFirst(recentLines.count - maxLines)
        }
        rewriteLogFile()
    }

    func recentLogText() -> String {
        recentLines.joined(separator: "\n")
    }

    func recentLogLines(limit: Int = 80) -> [String] {
        Array(recentLines.suffix(limit))
    }

    func copyRecentLogsToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(recentLogText(), forType: .string)
    }

    func copyDebugSnapshot(_ snapshot: DebugSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot), let text = String(data: data, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    func openLogDirectory() {
        NSWorkspace.shared.open(logDirectoryURL)
    }

    private func rewriteLogFile() {
        let body = recentLines.joined(separator: "\n")
        try? body.write(to: logFileURL, atomically: true, encoding: .utf8)
    }
}
