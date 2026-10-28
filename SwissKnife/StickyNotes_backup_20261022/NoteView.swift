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
    /// 勾选框相对基线的下沉偏移
    static let checkboxBaselineOffset: CGFloat = -5
    /// 勾选框内符号的绘制字号
    static let checkboxSymbolSize: CGFloat = 18
    static let imageDefaultWidth: CGFloat = 240
    static let imageMinWidth: CGFloat = 40
    static let imageMaxWidth: CGFloat = 600
    static let imageBaselineGap: CGFloat = 6
    static let fontSize: CGFloat = 14
}

/// 勾选框附件的统一 bounds (各处一致, 避免漏改)
func checkboxBounds() -> CGRect {
    CGRect(x: 0, y: Metrics.checkboxBaselineOffset,
           width: Metrics.checkboxSize, height: Metrics.checkboxSize)
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
        NSSize(width: Metrics.checkboxSize, height: Metrics.checkboxSize)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let color: NSColor = done
            ? NSColor.controlAccentColor : NSColor(white: 0.35, alpha: 0.5)
        let symbol = NSImage(systemSymbolName: done ? "checkmark.square.fill" : "square",
                             accessibilityDescription: nil)?
            .withSymbolConfiguration(
                .init(pointSize: Metrics.checkboxSymbolSize, weight: .medium)
                .applying(.init(paletteColors: [color])))
        symbol?.draw(in: cellFrame.insetBy(dx: 1, dy: 1))
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

        var replacements: [(NSRange, NSTextAttachment)] = []
        let ns = logical as NSString

        // 1) 待办行首前缀 → 勾选框附件
        var lineStart = 0
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

        /// 荧光笔是一个模式: 模式内只涂不改字, 这里是挡住所有文字改动的总闸门
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            !note.highlighterMode
        }

        func textDidChange(_ notification: Notification) {
            guard !syncingFromModel, let textView,
                  let storage = textView.textStorage else { return }
            // 输入 [] / 「」 / 【】 后免回车自动转待办。
            // 必须放在序列化判断之前: 中文输入法提交字符时 textDidChange
            // 可能先于序列化变化触发(serialized == note.text 提前 return),
            // 放在后面会导致括号行永远不被检查。
            autoConvertBracketLine()
            let serialized = AttachmentBuilder.serialize(storage: storage)
            // 划线/变灰是属性级变化, 不影响文本本身; 不相等才需要同步与重绘
            guard serialized != note.text else {
                dlog("文本-属性级变化", "仅划线/变灰/加粗自刷, 不重同步")
                return
            }
            dlog("文本同步", "\(note.text.prefix(12))… -> \(serialized.prefix(12))… (共\(serialized.count)字)")
            lastSyncedText = serialized
            note.text = serialized
            // 图片 token 被删除后, 清理 images 表和对应文件
            if note.syncImages() { NoteStore.shared.scheduleSave() }
            // 内容真的变了就强制重绘: 勾选替换附件字符时 NSTextStorage
            // 只报 .editedAttributes(字符数不变), didProcessEditing 可能不置位
            // needsRedraw, 导致划线/变灰/加粗延迟到下一次编辑才"突然"出现。
            needsRedraw = true
            redraw(in: textView)
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
        private func convertLineToTodo(lineStart: Int, lineEnd: Int) {
            guard let textView else { return }
            let cb = CheckboxAttachment(done: false)
            cb.bounds = checkboxBounds()
            cb.attachmentCell = makeCheckboxCell(done: false, for: cb)
            textView.insertText("", replacementRange:
                NSRange(location: lineStart, length: lineEnd - lineStart))
            textView.insertText(NSAttributedString(attachment: cb),
                                replacementRange: NSRange(location: lineStart, length: 0))
            textView.insertText(" ", replacementRange: NSRange(location: lineStart + 1, length: 0))
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
        // 状态栏 App 没有主菜单, ⌘V 的菜单快捷键绑定不存在,
        // key equivalent 不会分发到 paste:; 显式拦截, 否则 NSTextView
        // 找不到命令会播放"阻止"提示音。
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == [.command], event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return
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

    // MARK: 粘贴图片

    override func paste(_ sender: Any?) {
        if let image = firstImageFromPasteboard() {
            dlog("粘贴", "⌘V 命中图片, 交给 pasteImage")
            onPasteImage?(image)
            return
        }
        dlog("粘贴", "剪贴板未读到图片, 走默认文本粘贴")
        super.paste(sender)
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
