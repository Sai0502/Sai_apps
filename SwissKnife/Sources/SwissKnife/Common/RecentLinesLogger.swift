import Foundation

/// 通用「最近 N 行」文件日志，供 Zone / Wheel 等模块复用。
/// 内存保留最近 `maxLines` 行，并整体重写到 `debug.log`。
class RecentLinesLogger {
    let logDirectoryURL: URL
    let logFileURL: URL
    private let maxLines: Int
    private let formatter = ISO8601DateFormatter()
    private var recentLines: [String] = []

    init(directoryName: String, maxLines: Int = 300) {
        self.maxLines = maxLines
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        logDirectoryURL = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        logFileURL = logDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try? FileManager.default.createDirectory(
            at: logDirectoryURL,
            withIntermediateDirectories: true
        )
        if let contents = try? String(contentsOf: logFileURL, encoding: .utf8) {
            recentLines = Array(contents.split(separator: "\n").map(String.init).suffix(maxLines))
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

    func logDirectoryPath() -> String {
        logDirectoryURL.path
    }

    private func rewriteLogFile() {
        let body = recentLines.joined(separator: "\n")
        try? body.write(to: logFileURL, atomically: true, encoding: .utf8)
    }
}
