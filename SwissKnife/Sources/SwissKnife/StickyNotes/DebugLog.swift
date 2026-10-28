import AppKit

/// StickyNotes 模块调试日志：写关键操作到文件，供 SwissKnife「复制调试快照」汇总。
///
/// - 文件: ~/Library/Application Support/SwissKnife/StickyNotes/debug.log
///   - **追加模式**: 每次启动不清空, 写入"会话头"分隔; 便于回溯多次调试过程。
///   - 文件超过 2MB 时自动归档为 debug.old.log (旧文件删除, 只留最近两代)。
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
        // FileHandle(forWritingTo:) 不创建文件, 必须先确保文件存在
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
        // 超限归档
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        if size > 2 * 1024 * 1024 {
            let oldURL = dir.appendingPathComponent("debug.old.log")
            try? FileManager.default.removeItem(at: oldURL)
            try? FileManager.default.moveItem(at: fileURL, to: oldURL)
        }
        let header = "\n\n========== 会话启动 \(Date()) ==========\n"
        if let data = header.data(using: .utf8), let fh = try? FileHandle(forWritingTo: fileURL) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            _ = try? fh.write(contentsOf: data)
        }
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

/// 便捷缩写: 打印结构化流水 (带缩进的步骤日志, 便于在日志中识别执行链路)
func dflow(_ event: String, _ detail: String = "") {
    DebugLog.shared.log("  └ " + event, detail)
}
