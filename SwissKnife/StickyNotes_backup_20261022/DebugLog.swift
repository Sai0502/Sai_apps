import AppKit

/// StickyNotes 模块调试日志：写关键操作到文件，供 SwissKnife「复制调试快照」汇总。
///
/// - 文件: ~/Library/Application Support/SwissKnife/StickyNotes/debug.log (每次启动截断重写)
/// - 缓冲: 内存保留最近 500 条
final class DebugLog {
    static let shared = DebugLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let maxLines = 500
    let fileURL: URL
    private let started = Date()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("SwissKnife/StickyNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("debug.log")
        let header = "SwissKnife/StickyNotes 调试日志 启动于 \(Date())\n"
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        lines.append("== 启动 ==")
    }

    /// 记录一条日志。event 简短描述事件, detail 放关键上下文 (范围/数值/状态)。
    func log(_ event: String, _ detail: String = "") {
        lock.lock()
        defer { lock.unlock() }
        let stamp = Self.stampFormatter.string(from: Date())
        let line = detail.isEmpty ? "[\(stamp)] \(event)" : "[\(stamp)] \(event) | \(detail)"
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        if let data = (line + "\n").data(using: .utf8) {
            if let fh = try? FileHandle(forWritingTo: fileURL) {
                defer { try? fh.close() }
                _ = try? fh.seekToEnd()
                _ = try? fh.write(contentsOf: data)
            }
        }
    }

    /// 本次运行全部日志 (含启动信息)
    var contents: String {
        lock.lock()
        defer { lock.unlock() }
        var out = ["— StickyNotes 调试日志 (\(started)) —"]
        out += lines
        return out.joined(separator: "\n")
    }
}

/// 便捷缩写
func dlog(_ event: String, _ detail: String = "") {
    DebugLog.shared.log(event, detail)
}
