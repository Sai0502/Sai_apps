import SwiftUI
import AppKit

// MARK: - 全局尺寸常量

enum Metrics {
    static let minWidth: CGFloat = 184
    static let barHeight: CGFloat = 30
    static let cornerRadius: CGFloat = 14
    static let minHeight: CGFloat = 120
    static let autosaveDelay: TimeInterval = 1.0
    /// 待办勾选框尺寸 (v3.0.2: 28 → 20pt, 用户自调试点)
    static let checkboxSize: CGFloat = 20
    /// 勾选框相对基线的下沉偏移 (cellBaselineOffset, 负值=向下; 实测: 正值向上, 故取负)
    static let checkboxBaselineOffset: CGFloat = -5
    /// 勾选框右侧固定留白 (不可编辑的视觉间隔, 代替可删除的空格字符)
    static let checkboxTrailingGap: CGFloat = 6
    /// 勾选框内符号的绘制字号
    static let checkboxSymbolSize: CGFloat = 18
    static let imageDefaultWidth: CGFloat = 240
    static let imageMinWidth: CGFloat = 40
    static let imageMaxWidth: CGFloat = 600
    static let imageBaselineGap: CGFloat = 6
    static let fontSize: CGFloat = 14
}

/// 勾选框附件的统一 bounds (各处一致, 避免漏改)
/// 宽度 = 勾选框 + 右侧固定留白 (不可编辑的视觉间隔)
/// y 保持 0: 渲染垂直位置由 CheckboxCell.cellBaselineOffset 控制, 不靠 bounds
func checkboxBounds() -> CGRect {
    CGRect(x: 0, y: 0,
           width: Metrics.checkboxSize + Metrics.checkboxTrailingGap,
           height: Metrics.checkboxSize)
}

// MARK: - 磨砂玻璃背景 (NSVisualEffectView 桥接)

struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// macOS 27 起 isMovableByWindowBackground 不再把 SwiftUI 顶栏空白处当窗口背景, 显式接管拖动
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

// MARK: - 每日分隔线

/// 每日分隔线: 标记行文本格式 "── 10月27日 ──"(同年) / "── 2025年12月31日 ──"(跨年)。
/// 它是真实文本行(用户不可编辑/删除), 保存与序列化原样保留;
/// AttachmentBuilder.build 时渲染成灰色小字居中 + 上方大空隙(不可删除的"空行")。
enum DayDivider {
    static let prefix = "── "
    static let suffix = " ──"
    /// 分隔线上方的视觉空隙高度 (等于一个不可删除的空行)
    static let gapHeight: CGFloat = 26

    /// 生成某天的标记行文本
    static func marker(for date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let nowY = cal.component(.year, from: Date())
        let dateStr = y == nowY ? "\(m)月\(d)日" : "\(y)年\(m)月\(d)日"
        return "\(prefix)\(dateStr)\(suffix)"
    }

    /// 识别分隔行: 返回标记中的日期; 非分隔行返回 nil
    static func date(in line: String) -> Date? {
        guard line.hasPrefix(prefix), line.hasSuffix(suffix) else { return nil }
        let body = String(line.dropFirst(prefix.count).dropLast(suffix.count))
        let comps = body.replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
        let parts = comps.split(separator: "-").compactMap { Int($0) }
        let cal = Calendar.current
        var dc = DateComponents()
        if parts.count == 3 {
            dc.year = parts[0]; dc.month = parts[1]; dc.day = parts[2]
        } else if parts.count == 2 {
            dc.year = cal.component(.year, from: Date()); dc.month = parts[0]; dc.day = parts[1]
        } else { return nil }
        return cal.date(from: dc)
    }

    static func isDivider(_ line: String) -> Bool { date(in: line) != nil }
}

/// 把日期压成 (年,月,日) 三元组, 用于比较"同一天"
func dayTriple(_ date: Date) -> (Int, Int, Int) {
    let cal = Calendar.current
    return (cal.component(.year, from: date),
            cal.component(.month, from: date),
            cal.component(.day, from: date))
}

// MARK: - 便签主视图

struct NoteView: View {
    @ObservedObject var note: Note
    var onClose: () -> Void
    var onModeChange: (NoteMode) -> Void
    var onNewNote: () -> Void

    @State private var hovering = false
    @State private var eraseAllToken = 0

    private var highlighterMode: Bool { note.highlighterMode }

    private var accent: Color { Color(nsColor: note.theme.accent) }
    private var ink: Color { Color(nsColor: note.theme.text) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .background {
            ZStack {
                FrostedGlass()
                Color(nsColor: note.theme.background).opacity(0.82)
            }
        }
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: Metrics.cornerRadius,
                               bottomLeading: Metrics.cornerRadius,
                               bottomTrailing: Metrics.cornerRadius,
                               topTrailing: Metrics.cornerRadius),
            style: .continuous))
        .overlay {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: Metrics.cornerRadius,
                                   bottomLeading: Metrics.cornerRadius,
                                   bottomTrailing: Metrics.cornerRadius,
                                   topTrailing: Metrics.cornerRadius),
                style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.08),
                                 .black.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        }
        .onHover { h in
            withAnimation(.easeOut(duration: 0.18)) { hovering = h }
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            barContent(compact: false)
            barContent(compact: true)
        }
        .padding(.horizontal, 9)
        .frame(height: Metrics.barHeight)
        .background {
            ZStack {
                Color(nsColor: note.theme.bar).opacity(0.5)
                WindowDragArea()
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(ink.opacity(0.06)).frame(height: 0.5)
        }
    }

    private func barContent(compact: Bool) -> some View {
        HStack(spacing: 8) {
            // 关闭(删除)按钮
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(ink.opacity(hovering ? 0.08 : 0.04)))
            }
            .buttonStyle(.plain)
            .help("删除这张便签")

            // 新建便签
            Button(action: onNewNote) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(ink.opacity(hovering ? 0.08 : 0.04)))
            }
            .buttonStyle(.plain)
            .frame(width: 19)
            .help("新建便签")

            Spacer()

            if hovering && compact {
                if !highlighterMode {
                    Menu {
                        ForEach(NoteTheme.allCases, id: \.self) { theme in
                            Button { note.theme = theme } label: {
                                checkLabel(theme.displayName, note.theme == theme)
                            }
                        }
                        Divider()
                        modeItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ink.opacity(0.5))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22)
                    .help("颜色与窗口模式")
                }
            } else if hovering {
                ForEach(NoteTheme.allCases, id: \.self) { theme in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { note.theme = theme }
                        dlog("换主题", theme.displayName)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: theme.bar))
                            .frame(width: 11, height: 11)
                            .overlay {
                                Circle().strokeBorder(
                                    Color(nsColor: theme.accent)
                                        .opacity(note.theme == theme ? 0.9 : 0.25),
                                    lineWidth: note.theme == theme ? 1.5 : 1)
                            }
                            .scaleEffect(note.theme == theme ? 1.15 : 1)
                    }
                    .buttonStyle(.plain)
                    .help(theme.displayName)
                }

                Divider().frame(height: 11).opacity(0.4)

                Menu {
                    modeItems
                } label: {
                    Image(systemName: note.mode.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink.opacity(0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .help("窗口模式: \(note.mode.displayName)")
            }

            // 荧光笔
            // 荧光笔入口已从顶栏移除 (用户确认), 仍可用 ⌘⇧H / 右键菜单进入
        }
    }

    private var modeItems: some View {
        ForEach(NoteMode.allCases, id: \.self) { mode in
            Button { onModeChange(mode) } label: {
                checkLabel(mode.displayName, note.mode == mode)
            }
        }
    }

    @ViewBuilder
    private func checkLabel(_ title: String, _ checked: Bool) -> some View {
        if checked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // MARK: 内容区

    private var content: some View {
        HighlightedTextEditor(
            note: note,
            highlighterMode: $note.highlighterMode,
            eraseAllToken: eraseAllToken)
    }
}

/// 荧光笔笔头光标, 热点落在左下角的笔尖上
func highlighterCursor(_ color: NSColor) -> NSCursor {
    guard let symbol = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "荧光笔"),
          let image = symbol.withSymbolConfiguration(
            .init(pointSize: 17, weight: .regular)
            .applying(.init(paletteColors: [color.withAlphaComponent(1)])))
    else { return .crosshair }
    image.isTemplate = false
    return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: image.size.height - 2))
}

// MARK: - 附件组件 (勾选框 / 内嵌图片)

/// 勾选框附件: 文本流里行首 "[ ] "/"[x] " 的显示替身
final class CheckboxAttachment: NSTextAttachment {
    let done: Bool
    init(done: Bool) {
        self.done = done
        super.init(data: nil, ofType: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 勾选框的绘制与点击。NSTextAttachmentCell 没有 view 回调,
/// 交互走 draw + wantsToTrackMouse + trackMouse 协议。
final class CheckboxCell: NSTextAttachmentCell {
    var done = false
    var onToggle: (() -> Void)?

    override func cellSize() -> NSSize {
        NSSize(width: Metrics.checkboxSize + Metrics.checkboxTrailingGap,
               height: Metrics.checkboxSize)
    }

    /// 渲染位置控制: cell 相对文字基线的偏移 (这才是真正生效的垂直对齐参数)
    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: Metrics.checkboxBaselineOffset)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let color: NSColor = done
            ? NSColor.controlAccentColor : NSColor(white: 0.35, alpha: 0.5)
        let symbol = NSImage(systemSymbolName: done ? "checkmark.square.fill" : "square",
                             accessibilityDescription: nil)?
            .withSymbolConfiguration(
                .init(pointSize: Metrics.checkboxSymbolSize, weight: .medium)
                .applying(.init(paletteColors: [color])))
        // 左对齐: 符号只画在左侧勾选框区域, 右侧留白是"不可编辑的间隔"
        let box = NSRect(x: cellFrame.minX, y: cellFrame.minY,
                         width: Metrics.checkboxSize, height: Metrics.checkboxSize)
        symbol?.draw(in: box.insetBy(dx: 1, dy: 1))
    }

    override func wantsToTrackMouse(for event: NSEvent, in rect: NSRect,
                                    of controlView: NSView?,
                                    atCharacterIndex charIndex: Int) -> Bool {
        true
    }

    override func trackMouse(with event: NSEvent, in cellFrame: NSRect,
                             of controlView: NSView?, atCharacterIndex charIndex: Int,
                             untilMouseUp flag: Bool) -> Bool {
        onToggle?()
        return true
    }
}

/// 内嵌图片附件: 文本流里 "![<uuid>]" token 的显示替身
final class ImageAttachment: NSTextAttachment {
    let uuid: String
    init(uuid: String) {
        self.uuid = uuid
        super.init(data: nil, ofType: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 图片的绘制 + 右侧缩放手柄 (拖动右边框等比例缩放)。
/// cellFrame 是布局后的显示框, 拖动中锚定左侧 (cellFrame.minX 不变),
/// 用鼠标 x 与左缘的差值求新宽度。
final class ImageCell: NSTextAttachmentCell {
    var uuid = ""
    var attachedImage: NSImage?
    var ratio: CGFloat = 1
    var width: CGFloat = Metrics.imageDefaultWidth
    var onResize: ((CGFloat) -> Void)?

    private let handleWidth: CGFloat = 12

    override func cellSize() -> NSSize {
        NSSize(width: width, height: max(20, width / max(ratio, 0.01)))
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        if let image = attachedImage {
            drawImage(image, in: cellFrame, flipped: controlView?.isFlipped ?? false)
        }
        // 右侧缩放手柄的视觉提示
        guard cellFrame.width > 16 else { return }
        let color = NSColor(white: 0.5, alpha: 0.55)
        color.setStroke()
        let line = NSBezierPath()
        line.lineWidth = 1
        let x = cellFrame.maxX - 5
        line.move(to: NSPoint(x: x, y: cellFrame.minY + 3))
        line.line(to: NSPoint(x: x, y: cellFrame.maxY - 3))
        line.stroke()
        color.withAlphaComponent(0.4).setStroke()
        let dot = NSBezierPath(ovalIn: NSRect(
            x: x - 1.5, y: cellFrame.minY + 2.5, width: 3, height: 3))
        dot.stroke()
    }

    /// 用 CGImage 手动绘制, 方向完全可控。
    /// NSTextView 的绘制上下文是 flipped 的, 直接 NSImage.draw 会把
    /// 位图上下颠倒; 这里先平移到 cellFrame 左下原点, 再按视图是否
    /// flipped 翻转 y 轴, 保证图像像素方向与显示一致。
    private func drawImage(_ image: NSImage, in cellFrame: NSRect, flipped: Bool) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: cellFrame.minX,
                        y: flipped ? cellFrame.maxY : cellFrame.minY)
        if flipped { ctx.scaleBy(x: 1, y: -1) }
        let rect = CGRect(x: 0, y: 0, width: cellFrame.width, height: cellFrame.height)
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cg, in: rect)
        } else {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        ctx.restoreGState()
    }

    override func wantsToTrackMouse(for event: NSEvent, in rect: NSRect,
                                    of controlView: NSView?,
                                    atCharacterIndex charIndex: Int) -> Bool {
        guard let controlView else { return false }
        let p = controlView.convert(event.locationInWindow, from: nil)
        return p.x >= rect.maxX - handleWidth
    }

    override func trackMouse(with event: NSEvent, in cellFrame: NSRect,
                             of controlView: NSView?, atCharacterIndex charIndex: Int,
                             untilMouseUp flag: Bool) -> Bool {
        guard let controlView else { return false }
        // 只在手柄区域启动拖动
        let p = controlView.convert(event.locationInWindow, from: nil)
        guard p.x >= cellFrame.maxX - handleWidth else { return false }

        let anchor = cellFrame.minX
        while true {
            guard let next = controlView.window?
                .nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if next.type == .leftMouseUp { break }
            let np = controlView.convert(next.locationInWindow, from: nil)
            let w = min(max(np.x - anchor, Metrics.imageMinWidth), Metrics.imageMaxWidth)
            onResize?(w)
        }
        return true
    }
}

// MARK: - 附件坐标映射

/// 附件字符在 textStorage 中占 1 位, 对应逻辑文本中的 token:
/// 勾选框 "[ ] "/"[x] " = 4 字符, 图片 "![<uuid>]" = 39 字符。
/// 该结构把 textStorage 坐标 ↔ 逻辑文本坐标互相换算, 高亮/加粗统一存逻辑坐标。
struct AttachmentMap {
    struct Entry {
        let textIndex: Int   // 附件字符在 textStorage 中的位置
        let offset: Int      // token 长度 - 1
    }
    let entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    init(storage: NSTextStorage) {
        var list: [Entry] = []
        let ns = storage.string as NSString
        storage.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: ns.length)
        ) { value, range, _ in
            guard range.length > 0, let attach = value as? NSTextAttachment else { return }
            let len: Int
            if attach is CheckboxAttachment { len = 4 }
            else if attach is ImageAttachment { len = 39 }
            else { len = 1 }
            list.append(Entry(textIndex: range.location, offset: len - 1))
        }
        entries = list.sorted { $0.textIndex < $1.textIndex }
    }

    private func offset(upTo textIndex: Int) -> Int {
        var sum = 0
        for e in entries where e.textIndex < textIndex { sum += e.offset }
        return sum
    }

    /// textStorage 坐标 → 逻辑坐标
    func logical(_ i: Int) -> Int { i + offset(upTo: i) }

    /// 逻辑坐标 → textStorage 坐标 (迭代收敛)
    func text(_ i: Int) -> Int {
        var t = i
        while true {
            let nt = i - offset(upTo: t)
            if nt == t { return t }
            t = nt
        }
    }

    func logicalRange(_ r: NSRange) -> NSRange {
        let start = logical(r.location)
        let end = logical(r.location + r.length)
        return NSRange(location: start, length: end - start)
    }

    func textRange(_ r: NSRange) -> NSRange {
        let start = text(r.location)
        let end = text(r.location + r.length)
        return NSRange(location: start, length: end - start)
    }
}

// MARK: - 逻辑文本 ↔ 附件文本 构建与序列化

enum AttachmentBuilder {
    /// 把逻辑文本 (含 "[ ] "/"![<uuid>]" token) 构建成含附件的富文本
    static func build(logical: String, note: Note,
                      onResize: ((String, CGFloat) -> Void)? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: logical)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.5
        let full = NSRange(location: 0, length: (logical as NSString).length)
        result.addAttributes([
            .font: NSFont.systemFont(ofSize: Metrics.fontSize),
            .foregroundColor: note.theme.text,
            .paragraphStyle: paragraph
        ], range: full)

        // 0) 分隔行样式覆盖: 灰色小字居中, 第一条分隔行无上方空隙,
        //    其余分隔行上方留大空隙 (视觉上的不可删除空行)
        let ns = logical as NSString
        var lineStart = 0
        var firstDividerSeen = false
        for i in 0...ns.length {
            if i == ns.length || ns.character(at: i) == 0x0A {
                let lineRange = NSRange(location: lineStart, length: i - lineStart)
                let line = ns.substring(with: lineRange)
                if DayDivider.isDivider(line) {
                    let dp = NSMutableParagraphStyle()
                    dp.alignment = .center
                    dp.lineSpacing = 4.5
                    if firstDividerSeen { dp.paragraphSpacingBefore = DayDivider.gapHeight }
                    firstDividerSeen = true
                    result.addAttributes([
                        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: dp
                    ], range: lineRange)
                }
                lineStart = i + 1
            }
        }

        var replacements: [(NSRange, NSTextAttachment)] = []

        // 1) 待办行首前缀 → 勾选框附件
        lineStart = 0
        for i in 0...ns.length {
            if i == ns.length || ns.character(at: i) == 0x0A {
                if i > lineStart {
                    let line = ns.substring(with: NSRange(location: lineStart, length: i - lineStart))
                    var prefixLen = 0
                    var done = false
                    if line.hasPrefix("[ ] ") {
                        prefixLen = 4
                    } else if line.hasPrefix("[x] ") || line.hasPrefix("[X] ") {
                        prefixLen = 4
                        done = true
                    }
                    if prefixLen > 0 {
                        let attach = CheckboxAttachment(done: done)
                        attach.bounds = checkboxBounds()
                        attach.attachmentCell = checkboxCell(attach)
                        replacements.append((NSRange(location: lineStart, length: prefixLen), attach))
                    }
                }
                lineStart = i + 1
            }
        }

        // 2) 图片 token → 图片附件
        if let pattern = try? NSRegularExpression(pattern: #"!\[([0-9A-Fa-f-]{36})\]"#) {
            pattern.enumerateMatches(in: logical, range: full) { m, _, _ in
                guard let m, m.numberOfRanges > 1 else { return }
                let uuid = ns.substring(with: m.range(at: 1))
                guard let meta = note.images[uuid] else { return }
                let width = min(max(meta.width, Metrics.imageMinWidth), Metrics.imageMaxWidth)
                let height = width / max(meta.ratio, 0.01)
                let attach = ImageAttachment(uuid: uuid)
                attach.bounds = CGRect(x: 0, y: -height + Metrics.imageBaselineGap,
                                       width: width, height: height)
                attach.attachmentCell = imageCell(attach, meta: meta, onResize: onResize)
                replacements.append((m.range(at: 0), attach))
            }
        }

        // 从后往前替换, 避免坐标错乱
        for (range, attach) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: NSAttributedString(attachment: attach))
        }
        if !replacements.isEmpty {
            dlog("构建富文本", "文本=\(logical.count)字 附件=\(replacements.count)个")
        }
        return result
    }

    private static func checkboxCell(_ attach: CheckboxAttachment) -> CheckboxCell {
        let cell = CheckboxCell()
        cell.done = attach.done
        return cell
    }

    private static func imageCell(_ attach: ImageAttachment, meta: NoteImage,
                                  onResize: ((String, CGFloat) -> Void)? = nil) -> ImageCell {
        let cell = ImageCell()
        cell.uuid = attach.uuid
        cell.attachedImage = ImageStore.shared.load(meta.file)
        cell.ratio = meta.ratio
        cell.width = meta.width
        // ImageCell.onResize 只收宽度, uuid 由 cell 自己携带
        cell.onResize = onResize == nil ? nil : { [uuid = attach.uuid] w in onResize?(uuid, w) }
        return cell
    }

    /// 把 textStorage (含附件字符) 序列化成逻辑文本
    static func serialize(storage: NSTextStorage) -> String {
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result = ""
        var pos = 0
        storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
            result += ns.substring(with: NSRange(location: pos, length: range.location - pos))
            if let a = value as? CheckboxAttachment {
                result += a.done ? "[x] " : "[ ] "
            } else if let a = value as? ImageAttachment {
                result += "![\(a.uuid)]"
            } else if value != nil {
                result += "\u{FFFC}"
            } else {
                // value=nil 的普通文字区间：把整个区间的文字拼进来
                result += ns.substring(with: range)
            }
            pos = NSMaxRange(range)
        }
        if pos < full.length {
            result += ns.substring(with: NSRange(location: pos, length: full.length - pos))
        }
        return result
    }
}

// MARK: - 带荧光笔与附件的原生文字编辑器

struct HighlightedTextEditor: NSViewRepresentable {
    let note: Note
    @Binding var highlighterMode: Bool
    let eraseAllToken: Int   // 顶栏「清空全部」按钮的信号, 值变了就执行一次

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = HighlighterTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 9, height: 8)
        textView.font = .systemFont(ofSize: Metrics.fontSize)
        textView.textColor = note.theme.text
        textView.insertionPointColor = note.theme.accent
        textView.textStorage?.setAttributedString(AttachmentBuilder.build(
            logical: note.text, note: note,
            onResize: { [weak c = context.coordinator] uuid, w in
                c?.resizeImage(uuid, width: w)
            }))

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.5
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: Metrics.fontSize),
            .foregroundColor: note.theme.text,
            .paragraphStyle: paragraph
        ]

        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.lastSyncedText = note.text
        context.coordinator.attachmentMap = AttachmentMap(storage: textView.textStorage!)

        let c = context.coordinator
        textView.onPaint = { [weak c] in c?.paint($0) }
        textView.onErase = { [weak c] in c?.erase($0) }
        textView.onEraseSelection = { [weak c] in c?.eraseSelection($0) }
        textView.onEraseAll = { [weak c] in c?.eraseAll() }
        textView.onModeChange = { [weak c] in c?.setMode($0) }
        textView.hasHighlight = { [weak c] in c?.hasHighlight(in: $0) ?? false }
        textView.onToggleBold = { [weak c] in c?.toggleBold($0) }
        textView.isBold = { [weak c] range in
            guard let c else { return false }
            return c.bolds.coversFully(range)
        }
        textView.onPasteImage = { [weak c] in c?.pasteImage($0) }
        textView.onInsertNewline = { [weak c] in c?.handleTodoNewline() ?? false }

        scrollView.documentView = textView
        context.coordinator.refreshAttachmentActions()
        context.coordinator.applyState(to: textView)
        // 启动即归一化: 打开便签时按行创建时间生成/修复每日分隔线
        context.coordinator.normalizeOnLoad()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? HighlighterTextView,
              let storage = textView.textStorage else { return }

        let serialized = AttachmentBuilder.serialize(storage: storage)
        if serialized != note.text, note.text != context.coordinator.lastSyncedText {
            let caret = textView.selectedRange().location
            context.coordinator.syncingFromModel = true
            storage.setAttributedString(AttachmentBuilder.build(
                logical: note.text, note: note,
                onResize: { [weak c = context.coordinator] uuid, w in
                    c?.resizeImage(uuid, width: w)
                }))
            context.coordinator.syncingFromModel = false
            context.coordinator.lastSyncedText = note.text
            context.coordinator.attachmentMap = AttachmentMap(storage: storage)
            textView.setSelectedRange(
                NSRange(location: min(caret, (textView.string as NSString).length), length: 0))
            context.coordinator.refreshAttachmentActions()
            context.coordinator.invalidateDrawing()
        }
        if context.coordinator.eraseToken != eraseAllToken {
            context.coordinator.eraseToken = eraseAllToken
            DispatchQueue.main.async { [weak c = context.coordinator] in c?.eraseAll() }
        }
        context.coordinator.applyState(to: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: HighlightedTextEditor
        weak var textView: HighlighterTextView?
        var syncingFromModel = false
        var eraseToken: Int
        var lastSyncedText: String?
        var attachmentMap = AttachmentMap(entries: [])

        // 最近一次字符编辑的信息 (didProcessEditing 记录, textDidChange 消费)
        private var lastEditRange: NSRange?
        private var lastEditDelta = 0

        private var drawn: [TextHighlight] = []
        private var drawnBolds: [TextHighlight] = []
        private var drawnColor: NSColor?
        private var needsRedraw = true

        private var note: Note { parent.note }
        /// bolds 访问入口 (菜单/闭包需要跨类型读取)
        var bolds: [TextHighlight] { note.bolds }

        init(_ parent: HighlightedTextEditor) {
            self.parent = parent
            self.eraseToken = parent.eraseAllToken
        }

        func applyState(to textView: HighlighterTextView) {
            textView.highlightMode = note.highlighterMode
            textView.textColor = note.theme.text
            textView.insertionPointColor = note.theme.accent
            textView.highlighterColor = note.theme.highlighter
            textView.typingAttributes[.foregroundColor] = note.theme.text
            redraw(in: textView)
        }

        func invalidateDrawing() { needsRedraw = true }

        // MARK: 文字同步

        /// 荧光笔是一个模式: 模式内只涂不改字, 这里是挡住所有文字改动的总闸门;
        /// 每日分隔线是系统行, 普通编辑不得触及 (整块删除/全选删除放行)。
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            if note.highlighterMode { return false }
            if dividerEditBlocked(textView: textView, range: range,
                                  replacement: replacementString) {
                dlog("分隔线-拦截", "range=\(range) 触及分隔行, 已拒绝")
                return false
            }
            return true
        }

        /// 编辑是否触及分隔行 (整块删除/全选删除放行)
        private func dividerEditBlocked(textView: NSTextView, range: NSRange,
                                        replacement: String?) -> Bool {
            guard let storage = textView.textStorage else { return false }
            let ns = storage.string as NSString
            // 全选删除放行 (用户可一次清空整张便签)
            if range.location == 0 && range.length == ns.length
                && (replacement?.isEmpty ?? true) { return false }
            // 逐行检查: 编辑 range 是否触及分隔行
            var lineStart = 0
            for i in 0...ns.length {
                if i == ns.length || ns.character(at: i) == 0x0A {
                    let lineRange = NSRange(location: lineStart, length: i - lineStart)
                    let line = ns.substring(with: lineRange)
                    if DayDivider.isDivider(line) {
                        let touches: Bool
                        if range.length > 0 {
                            touches = NSIntersectionRange(range, lineRange).length > 0
                        } else {
                            touches = lineRange.location <= range.location
                                && range.location <= NSMaxRange(lineRange)
                        }
                        if touches {
                            // 整块删除放行: range 完整覆盖"该分隔行 + 其后到下一分隔行的所有行"
                            if range.length > 0,
                               let blockEnd = nextDividerStart(ns, after: i),
                               range.location <= lineStart,
                               NSMaxRange(range) >= blockEnd {
                                return false
                            }
                            return true
                        }
                    }
                    lineStart = i + 1
                }
            }
            return false
        }

        /// 从某行之后查找下一个分隔行的行首偏移 (找不到返回全文末尾)
        private func nextDividerStart(_ ns: NSString, after lineIndex: Int) -> Int? {
            var lineStart = 0
            var idx = 0
            for i in 0...ns.length {
                if i == ns.length || ns.character(at: i) == 0x0A {
                    if idx > lineIndex {
                        let line = ns.substring(with: NSRange(location: lineStart, length: i - lineStart))
                        if DayDivider.isDivider(line) { return lineStart }
                        return i  // 下一分隔行前的行首 (即本行的行首偏移起点)
                    }
                    idx += 1
                    lineStart = i + 1
                }
            }
            return ns.length
        }

        func textDidChange(_ notification: Notification) {
            guard !syncingFromModel, let textView,
                  let storage = textView.textStorage else { return }
            // 输入 [] / 「」 / 【】 后免回车自动转待办。
            // 必须放在序列化判断之前: 中文输入法提交字符时 textDidChange
            // 可能先于序列化变化触发(serialized == note.text 提前 return),
            // 放在后面会导致括号行永远不被检查。
            autoConvertBracketLine()

            // 捕获本次字符编辑信息 (可能已在上一次 textDidChange 中消费)
            let editRange = lastEditRange
            let editDelta = lastEditDelta
            lastEditRange = nil
            lastEditDelta = 0

            let serialized = AttachmentBuilder.serialize(storage: storage)
            // 划线/变灰是属性级变化, 不影响文本本身; 有字符编辑或文本变化才继续
            guard serialized != note.text || editRange != nil else {
                dlog("文本-属性级变化", "仅划线/变灰/加粗自刷, 不重同步")
                return
            }
            dlog("文本同步", "\(note.text.prefix(12))… -> \(serialized.prefix(12))… (共\(serialized.count)字)")
            // 先捕获编辑前的旧文本与旧时间戳 (供增量重算), 再更新状态
            let oldText = lastSyncedText ?? serialized
            let oldDates = note.lineCreatedAt
            lastSyncedText = serialized
            note.text = serialized

            // ===== 每日分隔线: 时间戳维护 + 新行置顶 + 分隔行自动维护 =====
            if serialized.isEmpty {
                // 全选删除/清空: 没有任何内容行, 也不保留任何分隔线
                note.lineCreatedAt = []
            } else if let editRange {
                let stamp = Date()
                note.lineCreatedAt = reconcileLineDates(
                    oldText: oldText, newText: serialized,
                    stamp: stamp, oldDates: oldDates)
                let caret = caretLineHint()
                dlog("分隔线-流水", "编辑@(行\(caret.line),列\(caret.col)) stamp=\(DayDivider.marker(for: stamp)) 文本=\(serialized.replacingOccurrences(of: "\n", with: "⏎").prefix(40))")
                let hint = dailyLayout(stamp: stamp, caretLine: caret.line, caretCol: caret.col)
                if let hint {
                    // 置顶/分隔线增删需要重建文本。
                    // 用 beginEditing + replaceCharacters 走正规编辑路径同步重建:
                    // setAttributedString 会重置 NSTextView 的输入状态导致丢字。
                    // hint 是"重建后光标应处的物理偏移" (normalizeDividers 算出)。
                    dlog("分隔线-重建", "置顶/分隔线变化 → 光标偏移 \(hint)")
                    rebuildFromModel(caretOffset: hint)
                } else {
                    dflow("结构不变", "无需重建, 光标保持原位")
                }
            }
            // ===== 结束 =====

            // 图片 token 被删除后, 清理 images 表和对应文件
            if note.syncImages() { NoteStore.shared.scheduleSave() }
            // 内容真的变了就强制重绘: 勾选替换附件字符时 NSTextStorage
            // 只报 .editedAttributes(字符数不变), didProcessEditing 可能不置位
            // needsRedraw, 导致划线/变灰/加粗延迟到下一次编辑才"突然"出现。
            needsRedraw = true
            redraw(in: textView)
        }

        /// 当前光标所在逻辑行号 + 行内偏移 (重建前记录, 置顶后按"行首+偏移"还原)
        private func caretLineHint() -> (line: Int, col: Int) {
            guard let textView else { return (0, 0) }
            let loc = textView.selectedRange().location
            let ns = textView.string as NSString
            var line = 0
            var lineStart = 0
            for i in 0..<min(loc, ns.length) where ns.character(at: i) == 0x0A {
                line += 1
                lineStart = i + 1
            }
            return (line, loc - lineStart)
        }

        /// 用 note.text 重建 textStorage, 并把光标放到 caretOffset (物理偏移)。
        /// 走 beginEditing/replaceCharacters 正规编辑路径, 不重置输入状态。
        private func rebuildFromModel(caretOffset: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            syncingFromModel = true
            storage.beginEditing()
            let full = NSRange(location: 0, length: storage.length)
            storage.replaceCharacters(in: full, with: AttachmentBuilder.build(
                logical: note.text, note: note,
                onResize: { [weak c = self] uuid, w in c?.resizeImage(uuid, width: w) }))
            storage.endEditing()
            syncingFromModel = false
            lastSyncedText = note.text
            attachmentMap = AttachmentMap(storage: storage)
            let ns = note.text as NSString
            textView.setSelectedRange(NSRange(location: min(caretOffset, ns.length), length: 0))
            refreshAttachmentActions()
            invalidateDrawing()
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard !syncingFromModel else { return }
            // 任何编辑(含仅属性变化)都标记需要重绘; 附件字符替换字符数不变时
            // NSTextStorage 只报 .editedAttributes, 所以不能用 editedCharacters 挡。
            needsRedraw = true
            guard editedMask.contains(.editedCharacters) else {
                dlog("存储编辑-属性级", "mask=\(editedMask.rawValue) range=\(editedRange) delta=\(delta)")
                return
            }
            dlog("存储编辑", "mask=\(editedMask.rawValue) range=\(editedRange) delta=\(delta)")
            // 记录本次字符编辑, 供 textDidChange 做每日分隔线布局
            lastEditRange = editedRange
            lastEditDelta = delta
            // attachmentMap 此刻还是"编辑前"状态, 用它算被替换的旧文本 (逻辑坐标)
            let oldMap = attachmentMap
            let oldTextRange = NSRange(location: editedRange.location,
                                       length: max(0, editedRange.length - delta))
            let replaced = oldMap.logicalRange(oldTextRange)
            // 新长度需要用编辑后的附件表
            let newMap = AttachmentMap(storage: textStorage)
            let newLength = newMap.logicalRange(editedRange).length
            attachmentMap = newMap

            let shifted = note.highlights.shifting(replacing: replaced, newLength: newLength)
            if shifted != note.highlights { note.highlights = shifted }
            let shiftedBolds = note.bolds.shifting(replacing: replaced, newLength: newLength)
            if shiftedBolds != note.bolds { note.bolds = shiftedBolds }
            needsRedraw = true
        }

        // MARK: 启动归一化: 打开便签即按 lineCreatedAt 生成每日分隔线

        func normalizeOnLoad() {
            guard let textView, let storage = textView.textStorage,
                  !note.text.isEmpty else { return }
            note.ensureLineDates()
            let before = note.text
            _ = normalizeDividers(caretLine: nil)
            guard note.text != before else { return }
            dlog("启动-分隔线", "载入即归一化 \(before.prefix(12))… → \(note.text.prefix(12))…")
            syncingFromModel = true
            storage.beginEditing()
            let full = NSRange(location: 0, length: storage.length)
            storage.replaceCharacters(in: full, with: AttachmentBuilder.build(
                logical: note.text, note: note,
                onResize: { [weak c = self] uuid, w in c?.resizeImage(uuid, width: w) }))
            storage.endEditing()
            syncingFromModel = false
            lastSyncedText = note.text
            attachmentMap = AttachmentMap(storage: storage)
            refreshAttachmentActions()
            needsRedraw = true
            redraw(in: textView)
            NoteStore.shared.scheduleSave()
        }

        // MARK: 每日分隔线: 时间戳维护

        /// 根据一次字符编辑, 增量重算每行创建时间戳。
        /// 规则: 编辑区间之前的行原样; 被删除的行丢弃; 编辑起点行的残留保留原时间;
        /// 本次新产生的行 (回车/粘贴/换行) 记 stamp。
        /// 用"文本对齐"重算每行时间戳 (不依赖 didProcessEditing 的 range,
        /// 因为自动转待办等嵌套编辑会污染 range 记录, 导致行数误判)。
        /// 原理: 旧文本与新文本按行做"前缀 + 后缀"对齐 —— 两边相同的行
        /// 保留原时间戳, 中间变化区: 行数不变则逐行保留, 新增行用 stamp,
        /// 删除行移除。置顶/分隔线重建发生在 reconcile 之后, 不影响对齐。
        private func reconcileLineDates(oldText: String, newText: String,
                                        stamp: Date, oldDates: [Date]) -> [Date] {
            // 旧文本为空: 没有任何旧行, 新文本每行都是新行
            if oldText.isEmpty {
                let n = newText.components(separatedBy: "\n").count
                dlog("分隔线-时间戳", "空文本起始, 新 \(n) 行")
                return Array(repeating: stamp, count: n)
            }
            let oldLines = oldText.components(separatedBy: "\n")
            let newLines = newText.components(separatedBy: "\n")
            // 前缀对齐: 头部相同的行
            var p = 0
            while p < min(oldLines.count, newLines.count), oldLines[p] == newLines[p] {
                p += 1
            }
            // 后缀对齐: 尾部相同的行 (跳过已匹配的前缀)
            var oe = oldLines.count
            var ne = newLines.count
            while oe > p && ne > p, oldLines[oe - 1] == newLines[ne - 1] {
                oe -= 1; ne -= 1
            }
            var result: [Date] = []
            // 前缀行原样保留
            if p > 0, p <= oldDates.count {
                result.append(contentsOf: oldDates.prefix(p))
            }
            // 变化区: old[p..<oe] → new[p..<ne]
            let oldChanged = oe - p
            let newChanged = ne - p
            if oldChanged == newChanged {
                // 行数不变: 变化区行还在, 逐行保留原时间戳
                if oldChanged > 0, p + oldChanged <= oldDates.count {
                    result.append(contentsOf: oldDates[p..<(p + oldChanged)])
                }
            } else if oldChanged < newChanged {
                // 新增行: 先保留变化区里还存在的 old 行, 其余新行 stamp
                let keep = min(oldChanged, newChanged)
                if keep > 0, p + keep <= oldDates.count {
                    result.append(contentsOf: oldDates[p..<(p + keep)])
                }
                result.append(contentsOf: Array(repeating: stamp, count: newChanged - keep))
            } else {
                // 删除行: 变化区 old 行减少, 保留前面 keep 个 (合并行继承旧时间戳)
                let keep = min(oldChanged, newChanged)
                if keep > 0, p + keep <= oldDates.count {
                    result.append(contentsOf: oldDates[p..<(p + keep)])
                }
            }
            // 后缀行原样保留
            if oldDates.count > oe {
                result.append(contentsOf: oldDates.suffix(from: oe))
            }
            // 行数守恒: 防御性兜底 (正常路径已守恒)
            let need = newLines.count
            if result.count < need {
                result.append(contentsOf: Array(repeating: stamp, count: need - result.count))
            } else if result.count > need {
                result = Array(result.prefix(need))
            }
            dlog("分隔线-时间戳", "old=\(oldLines.count)行 new=\(newLines.count)行 变\(oldChanged)→\(newChanged) 前缀\(p)")
            return result
        }

        // MARK: 每日分隔线: 布局 (置顶 + 分隔行维护)

        /// 每次字符编辑后的日常布局:
        /// 1) 本次新增行 (回车/粘贴) 若不在自己日期的分组内 → 挪到顶部今天分组末尾;
        /// 2) 重建分隔行 (日期交界处补线, 空块自动消失)。
        /// 返回重建后光标应处的物理偏移 (nil = 无需重建文本)。
        private func dailyLayout(stamp: Date, caretLine: Int, caretCol: Int) -> Int? {
            // 防御: 行数与时间戳行数不一致时先对齐 (正常路径 reconcile 已守恒)
            let lines = note.text.components(separatedBy: "\n")
            if note.lineCreatedAt.count != lines.count {
                if note.lineCreatedAt.count < lines.count {
                    note.lineCreatedAt.append(contentsOf: Array(repeating: stamp,
                        count: lines.count - note.lineCreatedAt.count))
                } else {
                    note.lineCreatedAt = Array(note.lineCreatedAt.prefix(lines.count))
                }
            }
            // 1) 新行置顶
            let (newCaretLine, moved) = moveNewLinesToTop(stamp: stamp, caretLine: caretLine)
            // 2) 分隔行重建 (置顶后光标所在行变了 → 用新行号; 行内列偏移不变)
            return normalizeDividers(caretLine: moved ? newCaretLine : caretLine,
                                     caretCol: moved ? caretCol : caretCol)
        }

        /// 把本次新增行 (时间戳 == stamp 的连续块) 挪到属于它日期的分组末尾;
        /// 若分组不存在则挪到文档顶部 (分隔行由 normalize 补)。
        /// 注意: 块只取"内容行", 分隔行 (时间戳继承自跟随行) 必须排除,
        /// 否则置顶会把旧分隔线一起带走, 与 normalize 重插的分隔线重复。
        private func moveNewLinesToTop(stamp: Date, caretLine: Int) -> (Int, Bool) {
            var lines = note.text.components(separatedBy: "\n")
            var dates = note.lineCreatedAt
            let stampIdx = dates.enumerated().compactMap { $0.element == stamp ? $0.offset : nil }
            // 块 = stamp 区间内的内容行 (排除分隔行)
            let contentIdx = stampIdx.filter { !DayDivider.isDivider(lines[$0]) }
            guard let first = contentIdx.first, let last = contentIdx.max() else {
                return (caretLine, false)
            }
            let stampDay = dayTriple(stamp)

            // 新行上方最近分隔行的日期 (判断是否已在正确分组)
            var aboveDay: (Int, Int, Int)? = nil
            for i in stride(from: first - 1, through: 0, by: -1)
            where DayDivider.isDivider(lines[i]) {
                if let d = DayDivider.date(in: lines[i]) { aboveDay = dayTriple(d); break }
            }
            if let aboveDay, aboveDay == stampDay {
                dflow("置顶-跳过", "新行 \(first)...\(last) 已在 \(DayDivider.marker(for: stamp)) 分组")
                return (caretLine, false)
            }
            if aboveDay == nil {
                // 无分隔行: 顶部组首行日期
                var topDay: (Int, Int, Int)? = nil
                for (i, l) in lines.enumerated() where !DayDivider.isDivider(l) {
                    topDay = dayTriple(dates[i]); break
                }
                if let topDay, topDay == stampDay {
                    dflow("置顶-跳过", "顶部组即今天, 无需移动")
                    return (caretLine, false)
                }
            }

            // 目标插入点: 今天分组末尾 (今天分隔行之后到下一分隔行前); 无今天分隔行 → 顶部
            var targetInsert = 0
            var foundToday = false
            for (i, line) in lines.enumerated() {
                if DayDivider.isDivider(line), let d = DayDivider.date(in: line),
                   dayTriple(d) == stampDay {
                    var j = i + 1
                    while j < lines.count && !DayDivider.isDivider(lines[j]) { j += 1 }
                    targetInsert = j
                    foundToday = true
                    break
                }
            }
            if !foundToday { targetInsert = 0 }

            // 整段取走 (含夹在中间的分隔行一起移除, 分隔线由 normalize 重插)
            let wholeStart = stampIdx.min() ?? first
            let wholeEnd = stampIdx.max() ?? last
            var block: [String] = []
            var blockDatesArr: [Date] = []
            for i in wholeStart...wholeEnd where !DayDivider.isDivider(lines[i]) {
                block.append(lines[i])
                blockDatesArr.append(dates[i])
            }
            lines.removeSubrange(wholeStart...wholeEnd)
            dates.removeSubrange(wholeStart...wholeEnd)
            var ins = targetInsert
            if targetInsert > wholeStart { ins = targetInsert - (wholeEnd - wholeStart + 1) }
            lines.insert(contentsOf: block, at: ins)
            dates.insert(contentsOf: blockDatesArr, at: ins)
            note.text = lines.joined(separator: "\n")
            note.lineCreatedAt = dates
            dlog("分隔线-置顶", "内容行 \(first)...\(last) → 分组末尾 \(ins) (块\(block.count)行, 排除了分隔行)")
            return (ins, true)
        }

        /// 重建分隔行: 丢弃旧分隔行, 在每个日期块的顶部插入对应日期的标记行;
        /// 空块 (无内容行) 自然消失。同时按分隔行增删调整 highlights/bolds 偏移。
        /// 返回 caretLine 行重建后的物理偏移。
        private func normalizeDividers(caretLine: Int?, caretCol: Int = 0) -> Int? {
            let oldText = note.text
            let lines = note.text.components(separatedBy: "\n")
            let dates = note.lineCreatedAt
            dflow("重建-输入", "行数\(lines.count) 光标行\(caretLine.map(String.init) ?? "nil")列\(caretCol) 文本=\(note.text.replacingOccurrences(of: "\n", with: "⏎").prefix(50))")
            // 没有任何实质内容行 (纯空行/纯旧分隔线) → 整段清空, 不保留分隔线
            let hasContent = lines.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !DayDivider.isDivider($0)
            }
            guard hasContent else {
                if !note.text.isEmpty {
                    note.text = ""
                    note.lineCreatedAt = []
                    dlog("分隔线-重建", "内容为空, 清空")
                    return 0   // 需要重建 (清空 textStorage)
                }
                return nil
            }
            var out: [String] = []
            var outDates: [Date] = []
            var lastDay: (Int, Int, Int)? = nil
            var caretOutLine = 0
            var contentIdx = 0
            var caretFound = false

            for (i, line) in lines.enumerated() {
                if DayDivider.isDivider(line) { continue }   // 旧分隔行丢弃
                let day = dayTriple(dates[i])
                if lastDay == nil || day != lastDay! {
                    let m = DayDivider.marker(for: dates[i])
                    out.append(m); outDates.append(dates[i])
                    lastDay = day
                }
                if let cl = caretLine, contentIdx == cl {
                    caretOutLine = out.count
                    caretFound = true
                }
                out.append(line); outDates.append(dates[i])
                contentIdx += 1
            }
            // 只有结构真的变化 (置顶/分隔行增删) 才重建文本;
            // 同一天内普通输入不改结构, 返回 nil 让编辑流自然继续
            let structuralChanged = out != lines
            note.text = out.joined(separator: "\n")
            note.lineCreatedAt = outDates
            guard structuralChanged else { return nil }

            // 分隔行增删引起的高亮/加粗偏移调整
            if !note.highlights.isEmpty || !note.bolds.isEmpty {
                adjustRangesForDividers(oldText: oldText, newText: note.text)
            }
            // 计算 caretOutLine 行的物理偏移 = 行首 + 行内列偏移
            guard let cl = caretLine, caretFound else {
                dflow("重建-输出", "\(lines.count)行 → \(out.count)行 (无光标锚点)")
                return nil
            }
            let ns = note.text as NSString
            var off = 0
            var line = 0
            while line < caretOutLine, off < ns.length {
                let r = ns.range(of: "\n", options: [],
                                 range: NSRange(location: off, length: ns.length - off))
                if r.location == NSNotFound { break }
                off = r.location + 1
                line += 1
            }
            off = min(off + caretCol, ns.length)
            dlog("分隔线-重建", "\(lines.count)行 → \(out.count)行 光标行\(caretOutLine)列\(caretCol)@偏移\(off)")
            return off
        }

        /// 分隔行增删后, 重映射 highlights/bolds 的偏移。
        /// 原理: 内容行 (非分隔行) 顺序不变, 段所在内容行的"行首偏移"从旧文本映射到新文本。
        private func adjustRangesForDividers(oldText: String, newText: String) {
            // 内容行行首偏移数组 (跳过分隔行)
            func contentStarts(_ text: String) -> [Int] {
                var starts: [Int] = []
                var lineStart = 0
                let ns = text as NSString
                for i in 0...ns.length {
                    if i == ns.length || ns.character(at: i) == 0x0A {
                        let line = ns.substring(with: NSRange(location: lineStart, length: i - lineStart))
                        if !DayDivider.isDivider(line) { starts.append(lineStart) }
                        lineStart = i + 1
                    }
                }
                return starts
            }
            let oldStarts = contentStarts(oldText)
            let newStarts = contentStarts(newText)
            guard !oldStarts.isEmpty else { return }
            // 物理偏移 → 内容行号 (行首 <= pos 的最后一个内容行)
            func contentLine(of pos: Int, starts: [Int]) -> Int {
                var line = 0
                for s in starts where s <= pos { line += 1 }
                return max(0, line - 1)
            }
            func remap(_ ranges: [TextHighlight]) -> [TextHighlight] {
                ranges.compactMap { (h: TextHighlight) -> TextHighlight? in
                    let cl = contentLine(of: h.location, starts: oldStarts)
                    guard cl < oldStarts.count, cl < newStarts.count else { return nil }
                    let col = h.location - oldStarts[cl]
                    let newLoc = newStarts[cl] + col
                    let maxLen = (newText as NSString).length - newLoc
                    guard maxLen > 0 else { return nil }
                    let len = min(h.length, maxLen)
                    guard len > 0 else { return nil }
                    return TextHighlight(NSRange(location: newLoc, length: len))
                }
            }
            let h = remap(note.highlights)
            let b = remap(note.bolds)
            if h != note.highlights { note.highlights = h }
            if b != note.bolds { note.bolds = b }
        }

        // MARK: 回车 → 待办区段逻辑

        /// 回车三态:
        /// ① 手打 "[]"(或 "[ ]") 回车 → 该行转为待办行, 光标落到条目文字前;
        /// ② 待办行(内容非空)回车 → 新行自动补 "[ ] ";
        /// ③ 空待办行回车 → 退出待办区段 (走普通换行)。
        /// 返回 true 表示已处理 (吞掉这次换行)。
        func handleTodoNewline() -> Bool {
            guard let textView, !note.highlighterMode else { return false }
            let sel = textView.selectedRange()
            guard sel.length == 0 else { return false }
            let caret = sel.location
            let ns = textView.string as NSString
            guard caret <= ns.length else { return false }
            var lineStart = caret
            while lineStart > 0, ns.character(at: lineStart - 1) != 0x0A { lineStart -= 1 }

            // ① 手打 "[]" / "[ ]" 回车 → 转为待办行
            let lineContent = ns.substring(
                with: NSRange(location: lineStart, length: caret - lineStart))
            let trimmed = lineContent.trimmingCharacters(in: .whitespaces)
            if trimmed == "[]" || trimmed == "[ ]" {
                dlog("回车-转待办", "行内容=「\(lineContent)」")
                convertLineToTodo(lineStart: lineStart, lineEnd: caret)
                return true
            }

            // ② ③ 只在待办行上生效
            guard lineStart < caret,
                  textView.textStorage?.attribute(
                      .attachment, at: lineStart, effectiveRange: nil) as? CheckboxAttachment
                      != nil
            else {
                dlog("回车-普通换行", "非待办行, 原样换行")
                return false
            }

            var hasContent = false
            if caret > lineStart + 1 {
                let content = ns.substring(with: NSRange(location: lineStart + 1,
                                                         length: caret - lineStart - 1))
                hasContent = !content.trimmingCharacters(in: .whitespaces).isEmpty
            }
            guard hasContent else {
                dlog("回车-退出待办", "空待办行, 回普通文字")
                return false
            }

            // 延续待办: 换行 + 新行插入未完成勾选框
            dlog("回车-延续待办", "新行自动补勾选框")
            textView.insertText("\n", replacementRange: sel)
            let newSel = textView.selectedRange()
            let cb = CheckboxAttachment(done: false)
            cb.bounds = checkboxBounds()
            cb.attachmentCell = makeCheckboxCell(done: false, for: cb)
            textView.insertText(NSAttributedString(attachment: cb), replacementRange: newSel)
            return true
        }

        /// 把 [lineStart, lineEnd) 的括号文本替换成勾选框附件 + 空格
        /// 必须"一次性替换"(beginEditing + 单次 replaceCharacters): 若分三步
        /// insertText, 每一步都会触发 textDidChange → 分隔线重建, 嵌套竞态
        /// 会导致重复附件/光标错位 (典型: 新的一天第一行输入 [] 变两个勾选框)。
        private func convertLineToTodo(lineStart: Int, lineEnd: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let range = NSRange(location: lineStart, length: lineEnd - lineStart)
            guard range.location + range.length <= storage.length else { return }
            let cb = CheckboxAttachment(done: false)
            cb.bounds = checkboxBounds()
            cb.attachmentCell = makeCheckboxCell(done: false, for: cb)
            let attachStr = NSMutableAttributedString(attachment: cb)
            attachStr.append(NSAttributedString(string: " "))
            storage.beginEditing()
            storage.replaceCharacters(in: range, with: attachStr)
            storage.endEditing()
            // 光标放到 附件+空格 之后 (textDidChange 会按 caretLineHint 校正)
            textView.setSelectedRange(NSRange(location: lineStart + 2, length: 0))
        }

        /// 输入括号后免回车自动转待办: 光标所在行恰好是 [] / [ ] / 「」 / 【】
        /// 之一 (中英文输入法都行) 就立刻转成勾选框, 不用等回车。
        /// 在 textDidChange 内容变化后调用; 转换会再触发一次编辑, 届时
        /// 行内容已变成附件+空格, 不会二次转换。
        func autoConvertBracketLine() {
            guard let textView, !note.highlighterMode else { return }
            let sel = textView.selectedRange()
            guard sel.length == 0 else { return }
            let caret = sel.location
            let ns = textView.string as NSString
            guard caret <= ns.length else { return }
            var lineStart = caret
            while lineStart > 0, ns.character(at: lineStart - 1) != 0x0A { lineStart -= 1 }
            let lineContent = ns.substring(
                with: NSRange(location: lineStart, length: caret - lineStart))
            let trimmed = lineContent.trimmingCharacters(in: .whitespaces)
            let brackets: Set<String> = ["[]", "[ ]", "「」", "【】"]
            // 命中或可能是候选前缀才打日志, 避免每次输入都刷屏
            let hit = brackets.contains(trimmed)
            let prefixLike = brackets.contains { $0.hasPrefix(trimmed) }
            if hit || prefixLike {
                dlog("自动转待办-检查",
                     "行内容=「\(lineContent)」 trimmed=「\(trimmed)」 命中=\(hit)")
            }
            guard hit else { return }
            dlog("自动转待办", "检测到「\(trimmed)」, 立即转勾选框")
            convertLineToTodo(lineStart: lineStart, lineEnd: caret)
        }

        /// 构造勾选框附件 cell; 点击回调从 cell 反向找到当前字符位置,
        /// 文字前后增删导致附件位置移动也不受影响。
        private func makeCheckboxCell(done: Bool, for attach: CheckboxAttachment) -> CheckboxCell {
            let cell = CheckboxCell()
            cell.done = done
            cell.onToggle = { [weak self] in self?.toggleCheckbox(cell) }
            return cell
        }

        // MARK: 勾选切换

        /// build 重建富文本后统一给勾选框 cell 挂上点击回调
        /// (cell 自己持 attachment 反向引用, 点击时实时定位, 位置移动也安全)
        func refreshAttachmentActions() {
            guard let textView, let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            storage.enumerateAttribute(
                .attachment, in: NSRange(location: 0, length: ns.length)
            ) { value, _, _ in
                if let cell = (value as? CheckboxAttachment)?.attachmentCell as? CheckboxCell {
                    cell.onToggle = { [weak self] in self?.toggleCheckbox(cell) }
                }
            }
        }

        func toggleCheckbox(_ cell: CheckboxCell) {
            guard let textView, let storage = textView.textStorage,
                  !note.highlighterMode,
                  let attach = cell.attachment as? CheckboxAttachment else {
                dlog("勾选-失败", "cell.attachment 不是 CheckboxAttachment 或模式/视图不满足")
                return
            }
            dlog("勾选点击", "done=\(attach.done ? "已完成" : "未完成")")
            // 附件字符会随编辑移动, 实时定位当前位置再替换
            var target = NSRange(location: NSNotFound, length: 0)
            let ns = storage.string as NSString
            storage.enumerateAttribute(
                .attachment, in: NSRange(location: 0, length: ns.length)
            ) { value, range, stop in
                if let a = value as? NSTextAttachment, a === attach {
                    target = range
                    stop.pointee = true
                }
            }
            guard target.location != NSNotFound else {
                dlog("勾选-失败", "在 textStorage 中找不到该附件")
                return
            }

            let newAttach = CheckboxAttachment(done: !attach.done)
            newAttach.bounds = checkboxBounds()
            newAttach.attachmentCell = makeCheckboxCell(done: !attach.done, for: newAttach)
            dlog("勾选切换", "附件@\(target.location) \(attach.done ? "[x]" : "[ ]") -> \(!attach.done ? "[x]" : "[ ]")")
            textView.insertText(NSAttributedString(attachment: newAttach),
                                replacementRange: target)
        }

        // MARK: 图片粘贴与缩放

        func pasteImage(_ image: NSImage) {
            guard let textView, !note.highlighterMode,
                  let saved = ImageStore.shared.save(image) else {
                dlog("粘贴图片-失败", "剪贴板无图或保存失败")
                return
            }
            dlog("粘贴图片", "uuid=\(saved.id.prefix(8)) ratio=\(saved.ratio)")
            note.images[saved.id] = NoteImage(file: saved.file,
                                              width: Metrics.imageDefaultWidth,
                                              ratio: saved.ratio)
            let height = Metrics.imageDefaultWidth / saved.ratio
            let attach = ImageAttachment(uuid: saved.id)
            attach.bounds = CGRect(x: 0, y: -height + Metrics.imageBaselineGap,
                                   width: Metrics.imageDefaultWidth, height: height)
            attach.attachmentCell = {
                let cell = ImageCell()
                cell.uuid = saved.id
                // 注意用 attachedImage 而不是继承的 image: draw 读的是 attachedImage
                cell.attachedImage = image
                cell.ratio = saved.ratio
                cell.width = Metrics.imageDefaultWidth
                cell.onResize = { [weak self] w in self?.resizeImage(saved.id, width: w) }
                return cell
            }()
            textView.insertText(NSAttributedString(attachment: attach),
                                replacementRange: textView.selectedRange())
        }

        func resizeImage(_ uuid: String, width: CGFloat) {
            guard var meta = note.images[uuid], let textView else { return }
            meta.width = width
            note.images[uuid] = meta
            dlog("缩放图片", "uuid=\(uuid.prefix(8)) width=\(Int(width))")
            let height = width / max(meta.ratio, 0.01)
            if let storage = textView.textStorage {
                let ns = storage.string as NSString
                storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ns.length)) {
                    value, range, stop in
                    guard let a = value as? ImageAttachment, a.uuid == uuid else { return }
                    // 必须同步更新 cell.width: TextKit 布局附件占位用的是
                    // cellSize()(读 cell.width), 只改 bounds 画面不会变化。
                    if let cell = a.attachmentCell as? ImageCell {
                        cell.width = width
                    }
                    a.bounds = CGRect(x: 0, y: -height + Metrics.imageBaselineGap,
                                      width: width, height: height)
                    textView.layoutManager?.invalidateLayout(forCharacterRange: range,
                                                              actualCharacterRange: nil)
                    stop.pointee = true
                }
            }
        }

        // MARK: 高亮增删

        func paint(_ range: NSRange) {
            guard range.length > 0, let textView else { return }
            let s = textView.string as NSString
            guard NSMaxRange(range) <= s.length else { return }
            let logical = attachmentMap.logicalRange(range)
            let pieces = lineSegments(logical, in: s)
            guard !pieces.isEmpty else { return }
            dlog("涂色", "textStorage=\(range) 逻辑=\(logical) 分段=\(pieces.count)")
            apply(pieces.reduce(note.highlights) { $0.adding($1) }, "涂色")
        }

        func erase(_ target: NSRange) {
            guard target.length > 0 else { return }
            apply(note.highlights.removing(attachmentMap.logicalRange(target)), "擦除高亮")
        }

        /// 跨行拖选时选区里夹着换行符, 给换行符上底色会让上一行的色块
        /// 一直铺到窗口右边缘。按换行切开, 再削掉每段两端的空白。
        private func lineSegments(_ range: NSRange, in s: NSString) -> [NSRange] {
            var out: [NSRange] = []
            var start = range.location
            for i in range.location..<NSMaxRange(range) {
                let c = s.character(at: i)
                guard c == 0x0A || c == 0x0D else { continue }
                if i > start { out.append(NSRange(location: start, length: i - start)) }
                start = i + 1
            }
            if NSMaxRange(range) > start {
                out.append(NSRange(location: start, length: NSMaxRange(range) - start))
            }
            return out.compactMap { trimmedBlanks($0, in: s) }
        }

        private func trimmedBlanks(_ r: NSRange, in s: NSString) -> NSRange? {
            var lo = r.location, hi = NSMaxRange(r)
            func blank(_ i: Int) -> Bool {
                guard let u = Unicode.Scalar(s.character(at: i)) else { return false }
                return CharacterSet.whitespaces.contains(u)
            }
            while lo < hi, blank(lo) { lo += 1 }
            while hi > lo, blank(hi - 1) { hi -= 1 }
            return hi > lo ? NSRange(location: lo, length: hi - lo) : nil
        }

        /// 右键「擦除所选高亮」: 没有选区时擦掉光标所在的那一整段
        func eraseSelection(_ selection: NSRange) {
            let logical = attachmentMap.logicalRange(selection)
            if logical.length > 0 { erase(selection); return }
            if let h = note.highlights.first(where: { NSLocationInRange(logical.location, $0.range) }) {
                apply(note.highlights.removing(h.range), "擦除高亮")
            }
        }

        func eraseAll() { apply([], "清空高亮") }

        func hasHighlight(in selection: NSRange) -> Bool {
            let logical = attachmentMap.logicalRange(selection)
            if logical.length == 0 {
                return note.highlights.contains { NSLocationInRange(logical.location, $0.range) }
            }
            return note.highlights.contains { NSIntersectionRange($0.range, logical).length > 0 }
        }

        // MARK: 加粗

        func toggleBold(_ range: NSRange) {
            guard range.length > 0 else {
                dlog("加粗切换-忽略", "选区为空")
                return
            }
            let logical = attachmentMap.logicalRange(range)
            guard logical.length > 0 else { return }
            if note.bolds.coversFully(logical) {
                dlog("加粗切换", "取消 range=\(range) logical=\(logical)")
                applyBolds(note.bolds.removing(logical), "取消加粗")
            } else {
                dlog("加粗切换", "启用 range=\(range) logical=\(logical)")
                applyBolds(note.bolds.adding(logical), "加粗")
            }
        }

        private func applyBolds(_ new: [TextHighlight], _ actionName: String) {
            let old = note.bolds
            guard old != new else { return }
            note.bolds = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.applyBolds(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { redraw(in: textView) }
        }

        func setMode(_ enabled: Bool) {
            note.highlighterMode = enabled
            textView?.highlightMode = enabled
        }

        /// 高亮改动的唯一出口: 写模型 + 注册撤销 + 重绘
        private func apply(_ new: [TextHighlight], _ actionName: String) {
            let old = note.highlights
            guard old != new else { return }
            note.highlights = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.apply(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { redraw(in: textView) }
        }

        // MARK: 绘制

        private func redraw(in textView: HighlighterTextView) {
            let color = note.theme.highlighter
            guard needsRedraw || drawn != note.highlights || drawnBolds != note.bolds
                    || drawnColor != color,
                  let lm = textView.layoutManager else {
                dlog("重绘-跳过", "needsRedraw=\(needsRedraw) 高亮=\(note.highlights.count)段 加粗=\(note.bolds.count)段")
                return
            }
            dlog("重绘", "高亮=\(note.highlights.count)段 加粗=\(note.bolds.count)段")
            if textView.hasMarkedText() { needsRedraw = true; return }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            let map = attachmentMap

            // 高亮
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            for h in note.highlights where h.length > 0 {
                let tr = map.textRange(h.range)
                if tr.length > 0, NSMaxRange(tr) <= full.length {
                    lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: tr)
                }
            }

            // 加粗: 持久属性 (v2.2.0 同方案; NSLayoutManager 的 temporary .font
            // 在本场景不渲染粗体, 所以改回 textStorage 直接写字体)
            applyBoldAttributes()

            // 已完成待办行: 划掉 + 降透明度。
            // 用持久属性而不是 temporary: NSLayoutManager 的临时属性
            // 不渲染 .foregroundColor, 只有持久字符属性能可靠变灰。
            applyDoneLineAttributes()

            drawn = note.highlights
            drawnBolds = note.bolds
            drawnColor = color
            needsRedraw = false
        }

        /// 加粗的持久属性重刷: 全量按 bolds 段设置 regular/bold 字体,
        /// 与划线同机制, 每次编辑后自愈 (打字打断粗体会在下次编辑补回)。
        /// 无条件先把整篇字体重置为 regular, 再对加粗段写 bold,
        /// 保证取消加粗/undo 后的残留粗体一定被清掉。
        private func applyBoldAttributes() {
            guard let textView, let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            guard full.length > 0 else { return }
            let regular = NSFont.systemFont(ofSize: Metrics.fontSize)
            let bold = NSFont.boldSystemFont(ofSize: Metrics.fontSize)

            if (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) != regular
                || !note.bolds.isEmpty {
                storage.addAttribute(.font, value: regular, range: full)
            }
            for b in note.bolds where b.length > 0 {
                let tr = attachmentMap.textRange(b.range)
                guard tr.length > 0, NSMaxRange(tr) <= full.length else { continue }
                if (storage.attribute(.font, at: tr.location, effectiveRange: nil) as? NSFont) == bold {
                    continue
                }
                storage.addAttribute(.font, value: bold, range: tr)
            }
            if !note.bolds.isEmpty {
                dlog("加粗应用", "bold 段=\(note.bolds.count)")
            }
        }

        /// 已完成待办行划线+变灰的持久属性重刷。
        /// 每次文本变化后全量重算: done 行划线+灰, 非 done 行恢复正文色+去划线。
        /// 属性写入走 editedAttributes, 不触发文本同步 (textDidChange 已按内容过滤),
        /// 因此不会循环。打字打断划线后下一次编辑自动补回, undo 勾选也会自动恢复。
        private func applyDoneLineAttributes() {
            guard let textView, let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            let gray = note.theme.text.withAlphaComponent(0.4)
            let strikeValue = NSUnderlineStyle.single.rawValue as NSNumber
            var doneCount = 0
            var openCount = 0
            var appliedCount = 0
            storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
                guard let a = value as? CheckboxAttachment else { return }
                if a.done { doneCount += 1 } else { openCount += 1 }
                var end = NSMaxRange(range)
                while end < ns.length, ns.character(at: end) != 0x0A { end += 1 }
                let line = NSRange(location: NSMaxRange(range), length: end - NSMaxRange(range))
                guard line.length > 0 else { return }
                let color: NSColor = a.done ? gray : note.theme.text
                let currentColor = storage.attribute(.foregroundColor, at: line.location,
                                                     effectiveRange: nil) as? NSColor
                if currentColor != color {
                    storage.addAttribute(.foregroundColor, value: color, range: line)
                    appliedCount += 1
                }
                let currentStrike = storage.attribute(.strikethroughStyle, at: line.location,
                                                      effectiveRange: nil) as? NSNumber
                if a.done {
                    if currentStrike?.intValue != strikeValue.intValue {
                        storage.addAttribute(.strikethroughStyle, value: strikeValue, range: line)
                        appliedCount += 1
                    }
                } else if currentStrike != nil {
                    storage.removeAttribute(.strikethroughStyle, range: line)
                    appliedCount += 1
                }
            }
            if doneCount + openCount > 0 {
                dlog("划线/变灰", "勾选框=\(doneCount)已完成+\(openCount)未完成, 写入\(appliedCount)处")
            }
        }
    }
}

// MARK: - 加粗快捷键 (硬编码 ⌘B, 不再可配置)

enum BoldShortcut {
    static let key: String = "b"
    static let modifiers: NSEvent.ModifierFlags = [.command]

    static func matches(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers?.lowercased() == key
            && event.modifierFlags
                .intersection([.command, .control, .option, .shift]) == modifiers
    }
}

// MARK: - 原生文本框 (荧光笔 + 附件交互)

final class HighlighterTextView: NSTextView, NSMenuDelegate {
    var highlightMode = false {
        didSet {
            guard oldValue != highlightMode else { return }
            window?.invalidateCursorRects(for: self)
            if !highlightMode { NSCursor.iBeam.set() }
        }
    }
    var highlighterColor: NSColor = .systemYellow
    var onPaint: ((NSRange) -> Void)?
    var onErase: ((NSRange) -> Void)?
    var onEraseSelection: ((NSRange) -> Void)?
    var onEraseAll: (() -> Void)?
    var onModeChange: ((Bool) -> Void)?
    var hasHighlight: ((NSRange) -> Bool)?
    var onToggleBold: ((NSRange) -> Void)?
    var isBold: ((NSRange) -> Bool)?
    var onPasteImage: ((NSImage) -> Void)?
    var onInsertNewline: (() -> Bool)?

    private var fullRange: NSRange { NSRange(location: 0, length: (string as NSString).length) }

    override func resetCursorRects() {
        super.resetCursorRects()
        if highlightMode { addCursorRect(visibleRect, cursor: highlighterCursor(highlighterColor)) }
    }

    // MARK: 模式内的鼠标与键盘

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard highlightMode else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        onPaint?(range)
        setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "h" {
            setMode(!highlightMode)
            return true
        }
        if BoldShortcut.matches(event), !highlightMode, isEditable {
            let selection = selectedRange()
            if selection.length > 0 { onToggleBold?(selection) }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if highlightMode, event.keyCode == 53 {   // Esc
            setMode(false)
            return
        }
        // 状态栏 App 没有主菜单, ⌘ 编辑命令的菜单快捷键绑定不存在:
        // NSTextView 把 selectAll:/copy:/undo: 等沿 nextResponder 链转发,
        // 链尾需要主菜单(Edit 菜单)兜底响应, 无主菜单时全部失效;
        // 打字/删除/回车由 NSTextView 自己处理, 不受影响。
        // 故与 ⌘V 同理, 显式拦截并直接调用对应方法。
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == [.command], let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "v":
                paste(nil)
                return
            case "a":
                selectAll(nil)
                return
            case "c":
                copy(nil)
                return
            case "x":
                cut(nil)
                return
            case "z":
                if event.modifierFlags.contains(.shift) {
                    undoManager?.redo()
                } else {
                    undoManager?.undo()
                }
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    /// 模式内退格键不删字, 改成擦掉光标前一个字的高亮并左移一格
    override func deleteBackward(_ sender: Any?) {
        guard highlightMode else { super.deleteBackward(sender); return }
        let sel = selectedRange()
        if sel.length > 0 {
            onErase?(sel)
            return
        }
        guard sel.location > 0 else { return }
        let prev = (string as NSString).rangeOfComposedCharacterSequence(at: sel.location - 1)
        onErase?(prev)
        setSelectedRange(NSRange(location: prev.location, length: 0))
    }

    // MARK: 回车: 待办区段逻辑交给 Coordinator

    override func insertNewline(_ sender: Any?) {
        if onInsertNewline?() == true { return }
        super.insertNewline(sender)
    }

    // MARK: 粘贴图片 / 过滤分隔行

    override func paste(_ sender: Any?) {
        if let image = firstImageFromPasteboard() {
            dlog("粘贴", "⌘V 命中图片, 交给 pasteImage")
            onPasteImage?(image)
            return
        }
        // 文本粘贴: 剥离分隔行 (分隔行是系统行, 不能粘进便签)
        if let text = NSPasteboard.general.string(forType: .string) {
            let filtered = text.components(separatedBy: "\n")
                .filter { !DayDivider.isDivider($0) }
                .joined(separator: "\n")
            if filtered != text {
                dlog("粘贴-过滤", "已剥离 \(text.components(separatedBy: "\n").count - filtered.components(separatedBy: "\n").count) 个分隔行")
                insertText(filtered, replacementRange: selectedRange())
                return
            }
        }
        dlog("粘贴", "剪贴板未读到图片, 走默认文本粘贴")
        super.paste(sender)
    }

    // MARK: 复制: 选中范围含分隔行时, 剥离后再写入剪贴板

    override func copy(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0, let text = textStorage?.string {
            let ns = text as NSString
            let sub = ns.substring(with: sel)
            if sub.components(separatedBy: "\n").contains(where: { DayDivider.isDivider($0) }) {
                let filtered = sub.components(separatedBy: "\n")
                    .filter { !DayDivider.isDivider($0) }
                    .joined(separator: "\n")
                dlog("复制-过滤", "已剥离分隔行")
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(filtered, forType: .string)
                return
            }
        }
        super.copy(sender)
    }

    /// 从剪贴板读图片, 三层兜底:
    /// ① readObjects 对象读取 (截图/拷贝图片最常见)
    /// ② PNG/TIFF 数据直接解码
    /// ③ 文件 URL (从访达/浏览器复制图片文件)
    /// 每层都打日志, 失败时能看出剪贴板里实际是什么。
    private func firstImageFromPasteboard() -> NSImage? {
        let pb = NSPasteboard.general
        let typeNames = pb.types?.map(\.rawValue).joined(separator: ",") ?? "无"
        dlog("粘贴-剪贴板", "types=\(typeNames)")

        // ① 对象读取
        if pb.canReadObject(forClasses: [NSImage.self], options: nil),
           let img = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            dlog("粘贴-剪贴板", "readObjects 读到 \(Int(img.size.width))x\(Int(img.size.height))")
            return img
        }
        // ② 数据解码 (剪贴板类型是 public.png/public.tiff 等原始数据时)
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
           let img = NSImage(data: data) {
            dlog("粘贴-剪贴板", "data 解码 \(Int(img.size.width))x\(Int(img.size.height))")
            return img
        }
        // ③ 文件 URL
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first(where: { $0.isFileURL }), let img = NSImage(contentsOf: url) {
            dlog("粘贴-剪贴板", "fileURL 解码 \(Int(img.size.width))x\(Int(img.size.height))")
            return img
        }
        dlog("粘贴-剪贴板", "三层读取都未命中图片")
        return nil
    }

    private func setMode(_ on: Bool) {
        highlightMode = on
        onModeChange?(on)
    }

    // MARK: 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.allowsContextMenuPlugIns = false
        if #available(macOS 15.2, *) {
            menu.automaticallyInsertsWritingToolsItems = false
        }
        menu.delegate = self

        let selection = selectedRange()
        addItem("撤销", action: #selector(performUndo), to: menu,
                enabled: undoManager?.canUndo == true)
        addItem("重做", action: #selector(performRedo), to: menu,
                enabled: undoManager?.canRedo == true)
        menu.addItem(.separator())
        addItem("剪切", action: #selector(cut(_:)), to: menu,
                enabled: !highlightMode && selection.length > 0)
        addItem("拷贝", action: #selector(copy(_:)), to: menu, enabled: selection.length > 0)
        addItem("粘贴", action: #selector(paste(_:)), to: menu,
                enabled: !highlightMode
                    && NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil))
        addItem("全选", action: #selector(selectAll(_:)), to: menu, enabled: !string.isEmpty)

        let bold = addItem(
            isBold?(selection) == true ? "取消加粗" : "加粗",
            action: #selector(toggleBoldFromMenu), to: menu,
            enabled: !highlightMode && isEditable && selection.length > 0)
        bold.image = NSImage(systemSymbolName: "bold", accessibilityDescription: nil)
        bold.keyEquivalent = BoldShortcut.key
        bold.keyEquivalentModifierMask = BoldShortcut.modifiers
        menu.addItem(.separator())

        let highlighter = addItem(
            highlightMode ? "退出荧光笔 (Esc)" : "荧光笔 (⌘⇧H)",
            action: #selector(toggleHighlighter), to: menu, enabled: true)
        highlighter.state = highlightMode ? .on : .off
        highlighter.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)

        let erase = addItem("擦除所选高亮", action: #selector(eraseSelected), to: menu,
                            enabled: hasHighlight?(selection) == true)
        erase.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: nil)

        let eraseEverything = addItem("清空全部高亮", action: #selector(eraseAll), to: menu,
                                      enabled: hasHighlight?(fullRange) == true)
        eraseEverything.image = NSImage(systemSymbolName: "eraser.fill", accessibilityDescription: nil)
        return menu
    }

    /// AppKit 会在文字菜单末尾自动追加"自动填充"和"服务"等项目;
    /// 这里仅保留便签真正需要的编辑与荧光笔操作。
    func menuNeedsUpdate(_ menu: NSMenu) {
        let allowedActions = Set([
            "performUndo", "performRedo", "cut:", "copy:", "paste:", "selectAll:",
            "toggleBoldFromMenu", "toggleHighlighter", "eraseSelected", "eraseAll"
        ])
        for item in menu.items.reversed() where !item.isSeparatorItem {
            guard let action = item.action,
                  allowedActions.contains(NSStringFromSelector(action)) else {
                menu.removeItem(item)
                continue
            }
        }

        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        for index in menu.items.indices.reversed() where index > 0 {
            if menu.items[index].isSeparatorItem && menu.items[index - 1].isSeparatorItem {
                menu.removeItem(at: index)
            }
        }
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, to menu: NSMenu,
                         enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    @objc private func performUndo() { undoManager?.undo() }
    @objc private func performRedo() { undoManager?.redo() }
    @objc private func toggleHighlighter() { setMode(!highlightMode) }
    @objc private func toggleBoldFromMenu() { onToggleBold?(selectedRange()) }
    @objc private func eraseSelected() { onEraseSelection?(selectedRange()) }
    @objc private func eraseAll() { onEraseAll?() }
}
