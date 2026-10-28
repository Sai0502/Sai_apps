import AppKit
import Combine

// MARK: - 颜色主题

enum NoteTheme: String, Codable, CaseIterable {
    case lemon, peach, mint, sky, lilac

    var displayName: String {
        switch self {
        case .lemon: return "柠檬黄"
        case .peach: return "蜜桃粉"
        case .mint:  return "薄荷绿"
        case .sky:   return "天空蓝"
        case .lilac: return "丁香紫"
        }
    }

    /// 便签主体背景色 (低饱和莫兰迪色, 叠在磨砂玻璃上)
    var background: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1)
        case .peach: return NSColor(red: 0.98, green: 0.93, blue: 0.91, alpha: 1)
        case .mint:  return NSColor(red: 0.92, green: 0.95, blue: 0.92, alpha: 1)
        case .sky:   return NSColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1)
        case .lilac: return NSColor(red: 0.95, green: 0.93, blue: 0.97, alpha: 1)
        }
    }

    /// 顶栏轻微加深的颜色
    var bar: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.93, green: 0.89, blue: 0.76, alpha: 1)
        case .peach: return NSColor(red: 0.95, green: 0.85, blue: 0.82, alpha: 1)
        case .mint:  return NSColor(red: 0.84, green: 0.90, blue: 0.85, alpha: 1)
        case .sky:   return NSColor(red: 0.83, green: 0.88, blue: 0.94, alpha: 1)
        case .lilac: return NSColor(red: 0.88, green: 0.84, blue: 0.94, alpha: 1)
        }
    }

    /// 同色系强调色 (勾选框、引用条、选中态)
    var accent: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.71, green: 0.58, blue: 0.22, alpha: 1)
        case .peach: return NSColor(red: 0.80, green: 0.47, blue: 0.40, alpha: 1)
        case .mint:  return NSColor(red: 0.36, green: 0.58, blue: 0.44, alpha: 1)
        case .sky:   return NSColor(red: 0.34, green: 0.53, blue: 0.74, alpha: 1)
        case .lilac: return NSColor(red: 0.55, green: 0.45, blue: 0.73, alpha: 1)
        }
    }

    /// 针对每种便签底色挑选的对比荧光色。
    /// 高亮只保存文字范围，切换主题时会自动改用这里的新颜色。
    var highlighter: NSColor {
        switch self {
        case .lemon: return NSColor(red: 1.00, green: 0.38, blue: 0.30, alpha: 0.44) // 珊瑚红
        case .peach: return NSColor(red: 1.00, green: 0.72, blue: 0.08, alpha: 0.56) // 琥珀黄
        case .mint:  return NSColor(red: 0.57, green: 0.36, blue: 1.00, alpha: 0.42) // 明亮紫
        case .sky:   return NSColor(red: 0.55, green: 0.86, blue: 0.22, alpha: 0.48) // 青柠绿
        case .lilac: return NSColor(red: 0.12, green: 0.78, blue: 0.69, alpha: 0.45) // 湖水青
        }
    }

    /// 正文文字颜色 (暖墨色, 深一点保证醒目)
    var text: NSColor {
        NSColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1)
    }
}

// MARK: - 窗口层级模式

enum NoteMode: String, Codable, CaseIterable {
    case floating   // 置顶悬浮
    case normal     // 普通窗口
    case desktop    // 贴在桌面

    var displayName: String {
        switch self {
        case .floating: return "置顶悬浮"
        case .normal:   return "普通窗口"
        case .desktop:  return "贴在桌面"
        }
    }

    var symbol: String {
        switch self {
        case .floating: return "pin.fill"
        case .normal:   return "macwindow"
        case .desktop:  return "square.grid.3x3.bottomright.filled"
        }
    }
}

// MARK: - 文字便签中的一段荧光/加粗标记

/// 文字便签中的一段荧光/加粗标记。范围使用 UTF-16，与 NSTextView/NSRange 一致。
struct TextHighlight: Codable, Equatable {
    var location: Int
    var length: Int

    var range: NSRange { NSRange(location: location, length: length) }

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }
}

extension Array where Element == TextHighlight {
    /// 并入一段, 与已有高亮相接的自动合成一段
    func adding(_ range: NSRange) -> [TextHighlight] {
        guard range.length > 0 else { return self }
        var out: [NSRange] = []
        for r in (map(\.range) + [range]).sorted(by: { $0.location < $1.location }) where r.length > 0 {
            if let last = out.last, r.location <= NSMaxRange(last) {
                out[out.count - 1] = NSUnionRange(last, r)
            } else {
                out.append(r)
            }
        }
        return out.map(TextHighlight.init)
    }

    /// 挖掉一段, 被从中间穿过的高亮断成两截
    func removing(_ range: NSRange) -> [TextHighlight] {
        guard range.length > 0 else { return self }
        return flatMap { h -> [NSRange] in
            let overlap = NSIntersectionRange(h.range, range)
            guard overlap.length > 0 else { return [h.range] }
            var parts: [NSRange] = []
            if h.location < overlap.location {
                parts.append(NSRange(location: h.location, length: overlap.location - h.location))
            }
            if NSMaxRange(overlap) < NSMaxRange(h.range) {
                parts.append(NSRange(location: NSMaxRange(overlap),
                                     length: NSMaxRange(h.range) - NSMaxRange(overlap)))
            }
            return parts
        }.map(TextHighlight.init)
    }

    func covers(_ range: NSRange) -> Bool {
        contains { NSIntersectionRange($0.range, range).length > 0 }
    }

    /// 整段都落在同一段标记之内 (adding 合并相邻段, 全覆盖时必在单段里)
    func coversFully(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        return contains { NSLocationInRange(range.location, $0.range)
            && NSMaxRange(range) <= NSMaxRange($0.range) }
    }

    /// 文字被替换后平移。落进替换区里的部分直接丢掉,
    /// 所以全选改写会让高亮自然清空, 不需要额外判断。
    func shifting(replacing old: NSRange, newLength: Int) -> [TextHighlight] {
        let delta = newLength - old.length
        let oldEnd = NSMaxRange(old)
        return flatMap { h -> [NSRange] in
            let r = h.range, hEnd = NSMaxRange(r)
            if hEnd <= old.location { return [r] }
            if r.location >= oldEnd { return [NSRange(location: r.location + delta, length: r.length)] }
            // 在高亮内部打字: 新字一并纳进这段高亮
            if old.length == 0 { return [NSRange(location: r.location, length: r.length + delta)] }
            var parts: [NSRange] = []
            if r.location < old.location {
                parts.append(NSRange(location: r.location, length: old.location - r.location))
            }
            if hEnd > oldEnd {
                parts.append(NSRange(location: oldEnd + delta, length: hEnd - oldEnd))
            }
            return parts
        }.map(TextHighlight.init)
    }
}

// MARK: - 图片模型

/// 便签里的一张内嵌图片。文件存 ~/Library/Application Support/StickyNotes/images/
struct NoteImage: Codable {
    var file: String
    var width: CGFloat    // 用户缩放后的显示宽度 (pt); 未缩放时为默认宽度
    var ratio: CGFloat    // 原图宽高比 (宽/高), 显示高度 = width / ratio
}

// MARK: - 便签模型

final class Note: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var text: String
    @Published var theme: NoteTheme
    @Published var mode: NoteMode
    @Published var highlights: [TextHighlight]
    @Published var bolds: [TextHighlight]
    /// 荧光笔模式。纯 UI 状态不进 Codable, 但要放在这里,
    /// 窗口层才能统一处理 Esc / ⌘⇧H。
    @Published var highlighterMode = false
    /// 内嵌图片表: key = text 里 "![<uuid>]" token 的 uuid
    @Published var images: [String: NoteImage] = [:]
    /// 每日分隔线功能: 每行的创建时间戳 (下标 = 行号, 与 text 按 \n 拆分的行一一对应)。
    /// 行创建后时间戳不再改变; 新行 (回车/粘贴/换行) = 创建时刻。
    @Published var lineCreatedAt: [Date] = []
    var frame: CGRect

    init(id: UUID = UUID(),
         text: String = "",
         theme: NoteTheme = .lemon,
         mode: NoteMode = .floating,
         highlights: [TextHighlight] = [],
         bolds: [TextHighlight] = [],
         images: [String: NoteImage] = [:],
         lineCreatedAt: [Date] = [],
         frame: CGRect = .zero) {
        self.id = id
        self.text = text
        self.theme = theme
        self.mode = mode
        self.highlights = highlights
        self.bolds = bolds
        self.images = images
        self.lineCreatedAt = lineCreatedAt
        self.frame = frame
    }

    /// 文本中所有图片 token 的 uuid 集合
    var imageTokens: Set<String> {
        guard text.contains("![") else { return [] }
        var out = Set<String>()
        let pattern = try? NSRegularExpression(pattern: #"!\[([0-9A-Fa-f-]{36})\]"#)
        let ns = text as NSString
        pattern?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges > 1 else { return }
            out.insert(ns.substring(with: m.range(at: 1)))
        }
        return out
    }

    /// 移除 text 中已无引用的 images 条目并删除对应文件。
    /// 返回是否有变化 (调用方据此决定是否触发保存)。
    @discardableResult
    func syncImages() -> Bool {
        guard !images.isEmpty else { return false }
        let used = imageTokens
        let stale = images.keys.filter { !used.contains($0) }
        guard !stale.isEmpty else { return false }
        for key in stale {
            if let file = images[key]?.file {
                ImageStore.shared.deleteFile(file)
            }
            images[key] = nil
        }
        return true
    }

    // Codable (手动实现, 因为 @Published 不能自动合成)
    // 旧数据里的 isCollapsed/snap/expandedFrame 等折叠字段不再读取,
    // 解码时被忽略, 老便签一律以展开态显示。
    enum CodingKeys: String, CodingKey {
        case id, text, theme, mode, highlights, bolds, images, lineCreatedAt
        case x, y, w, h
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let frame = CGRect(
            x: try c.decodeIfPresent(Double.self, forKey: .x) ?? 0,
            y: try c.decodeIfPresent(Double.self, forKey: .y) ?? 0,
            width: try c.decodeIfPresent(Double.self, forKey: .w) ?? 280,
            height: try c.decodeIfPresent(Double.self, forKey: .h) ?? 280
        )
        let text = try c.decode(String.self, forKey: .text)
        let textLength = (text as NSString).length
        func ranges(_ key: CodingKeys) throws -> [TextHighlight] {
            (try c.decodeIfPresent([TextHighlight].self, forKey: key) ?? [])
                .filter { $0.location >= 0 && $0.length > 0 && NSMaxRange($0.range) <= textLength }
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            text: text,
            theme: try c.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .lemon,
            mode: try c.decodeIfPresent(NoteMode.self, forKey: .mode) ?? .floating,
            highlights: try ranges(.highlights),
            bolds: try ranges(.bolds),
            images: try c.decodeIfPresent([String: NoteImage].self, forKey: .images) ?? [:],
            lineCreatedAt: try c.decodeIfPresent([Date].self, forKey: .lineCreatedAt) ?? [],
            frame: frame
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(theme, forKey: .theme)
        try c.encode(mode, forKey: .mode)
        if !highlights.isEmpty { try c.encode(highlights, forKey: .highlights) }
        if !bolds.isEmpty { try c.encode(bolds, forKey: .bolds) }
        if !images.isEmpty { try c.encode(images, forKey: .images) }
        if !lineCreatedAt.isEmpty { try c.encode(lineCreatedAt, forKey: .lineCreatedAt) }
        try c.encode(frame.origin.x, forKey: .x)
        try c.encode(frame.origin.y, forKey: .y)
        try c.encode(frame.width, forKey: .w)
        try c.encode(frame.height, forKey: .h)
    }

    // MARK: - 每日分隔线辅助

    /// text 按 \n 拆分的行数 (空文本 = 1 行)
    var lineCount: Int {
        let n = (text as NSString).length
        guard n > 0 else { return 1 }
        var count = 1
        for i in 0..<n where (text as NSString).character(at: i) == 0x0A { count += 1 }
        return count
    }

    /// 保证 lineCreatedAt 与行数一致 (旧数据缺失/长度不符时补齐为 now)
    func ensureLineDates() {
        let target = lineCount
        if lineCreatedAt.count == target { return }
        let now = Date()
        if lineCreatedAt.count < target {
            lineCreatedAt.append(contentsOf: Array(repeating: now, count: target - lineCreatedAt.count))
        } else {
            lineCreatedAt = Array(lineCreatedAt.prefix(target))
        }
    }
}

// MARK: - 历史归档

struct ArchivedNote: Codable, Identifiable {
    let id: UUID
    let text: String
    let theme: NoteTheme
    let highlights: [TextHighlight]
    let bolds: [TextHighlight]
    let images: [String: NoteImage]
    let lineCreatedAt: [Date]
    let deletedAt: Date

    init(id: UUID, text: String, theme: NoteTheme,
         highlights: [TextHighlight] = [], bolds: [TextHighlight] = [],
         images: [String: NoteImage] = [:], lineCreatedAt: [Date] = [],
         deletedAt: Date) {
        self.id = id
        self.text = text
        self.theme = theme
        self.highlights = highlights
        self.bolds = bolds
        self.images = images
        self.lineCreatedAt = lineCreatedAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, text, theme, highlights, bolds, images, lineCreatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        theme = try c.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .lemon
        let textLength = (text as NSString).length
        func ranges(_ key: CodingKeys) throws -> [TextHighlight] {
            (try c.decodeIfPresent([TextHighlight].self, forKey: key) ?? [])
                .filter { $0.location >= 0 && $0.length > 0 && NSMaxRange($0.range) <= textLength }
        }
        highlights = try ranges(.highlights)
        bolds = try ranges(.bolds)
        images = try c.decodeIfPresent([String: NoteImage].self, forKey: .images) ?? [:]
        lineCreatedAt = try c.decodeIfPresent([Date].self, forKey: .lineCreatedAt) ?? []
        deletedAt = try c.decode(Date.self, forKey: .deletedAt)
    }
}

// MARK: - 存储

final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    @Published private(set) var archived: [ArchivedNote] = []
    private var cancellables: [UUID: AnyCancellable] = [:]
    private var saveWorkItem: DispatchWorkItem?

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwissKnife/StickyNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var fileURL: URL { dir.appendingPathComponent("notes.json") }
    private var historyURL: URL { dir.appendingPathComponent("history.json") }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
            // 清理: 移除无引用的图片条目, 删除孤儿图片文件
            var used = Set<String>()
            for note in notes {
                note.syncImages()
                note.ensureLineDates()
                used.formUnion(note.images.keys)
            }
            ImageStore.shared.pruneOrphans(used: used)
            notes.forEach(observe)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? decoder.decode([ArchivedNote].self, from: data) {
            archived = decoded
        }
    }

    func add(_ note: Note) {
        notes.append(note)
        observe(note)
        scheduleSave()
    }

    func remove(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        cancellables[note.id] = nil
        scheduleSave()
    }

    /// 删除时归档: 有内容的便签移入历史 (图片文件跟随引用保留)
    func archive(_ note: Note) {
        guard !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        note.ensureLineDates()
        archived.insert(
            ArchivedNote(id: UUID(), text: note.text, theme: note.theme,
                         highlights: note.highlights, bolds: note.bolds,
                         images: note.images, lineCreatedAt: note.lineCreatedAt,
                         deletedAt: Date()),
            at: 0)
        saveHistory()
    }

    /// 从历史中取回 (返回归档内容, 由调用方重建便签)
    func unarchive(_ id: UUID) -> ArchivedNote? {
        guard let index = archived.firstIndex(where: { $0.id == id }) else { return nil }
        let item = archived.remove(at: index)
        saveHistory()
        return item
    }

    func removeArchived(_ id: UUID) {
        archived.removeAll { $0.id == id }
        saveHistory()
    }

    func removeAllArchived() {
        archived.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(archived) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func observe(_ note: Note) {
        // 内容/主题/模式变化后延迟自动保存
        cancellables[note.id] = note.objectWillChange
            .sink { [weak self] _ in self?.scheduleSave() }
    }

    /// 防抖: 停止输入 1 秒后写盘
    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
