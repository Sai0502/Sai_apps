import AppKit
import SwiftUI

/// 无边框但可输入、可拖动、可缩放的便签窗口
final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // 荧光笔的开关键在窗口这一层兜底 (没有 NSTextView 接管按键时)
    var onToggleHighlighter: (() -> Void)?
    /// 返回 true 表示这次 Esc 用来退出荧光笔了; 否则照常往下传,
    /// 免得吞掉输入框之类地方原本的 Esc。
    var onEscape: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "h" {
            onToggleHighlighter?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, onEscape?() == true { return }
        super.keyDown(with: event)
    }
}

/// 便签空白区的右键菜单: 每张便签统一提供
/// (文字上的菜单由 HighlighterTextView 自己弹, 落到这里的是空白区)
final class NoteHostingView: NSHostingView<NoteView> {
    weak var note: Note?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let note else {
            return super.menu(for: event)
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let um = window?.undoManager
        menu.addItem(item("撤销", enabled: um?.canUndo == true) { [weak um] in um?.undo() })
        menu.addItem(item("重做", enabled: um?.canRedo == true) { [weak um] in um?.redo() })
        menu.addItem(.separator())
        menu.addItem(item("剪切", enabled: false) {})
        menu.addItem(item("拷贝", enabled: false) {})
        menu.addItem(item("粘贴", enabled: false) {})
        menu.addItem(item("全选", enabled: false) {})
        let bold = item("加粗", symbol: "bold", enabled: false) {}
        bold.keyEquivalent = BoldShortcut.key
        bold.keyEquivalentModifierMask = BoldShortcut.modifiers
        menu.addItem(bold)
        menu.addItem(.separator())
        let toggle = item(note.highlighterMode ? "退出荧光笔 (Esc)" : "荧光笔 (⌘⇧H)",
                          symbol: "highlighter") { [weak note] in
            note?.highlighterMode.toggle()
            dlog("荧光笔", "右键菜单切换 -> \(!(note?.highlighterMode ?? false) ? "开" : "关")")
        }
        toggle.state = note.highlighterMode ? .on : .off
        menu.addItem(toggle)
        menu.addItem(item("擦除所选高亮", symbol: "eraser", enabled: false) {})
        menu.addItem(item("清空全部高亮", symbol: "eraser.fill",
                          enabled: !note.highlights.isEmpty) { [weak note] in
            note?.highlights = []
            dlog("清空高亮", "右键菜单")
        })
        return menu
    }

    private func item(_ title: String, symbol: String? = nil, enabled: Bool = true,
                      handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.isEnabled = enabled
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

final class NoteWindowController: NSWindowController, NSWindowDelegate {
    let note: Note
    private let onDelete: (Note) -> Void
    private let onNewNote: () -> Void

    init(note: Note, onDelete: @escaping (Note) -> Void, onNewNote: @escaping () -> Void) {
        self.note = note
        self.onDelete = onDelete
        self.onNewNote = onNewNote

        let window = NoteWindow(
            contentRect: note.frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.minSize = NSSize(width: Metrics.minWidth, height: Metrics.minHeight)
        window.delegate = self

        window.onToggleHighlighter = { [weak note] in
            note?.highlighterMode.toggle()
        }
        window.onEscape = { [weak note] in
            guard let note, note.highlighterMode else { return false }
            note.highlighterMode = false
            return true
        }

        let view = NoteView(
            note: note,
            onClose: { [weak self] in self?.confirmDelete() },
            onModeChange: { [weak self] mode in
                note.mode = mode
                self?.applyMode()
            },
            onNewNote: onNewNote
        )
        let hosting = NoteHostingView(rootView: view)
        hosting.note = note
        window.contentView = hosting
        applyMode()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 根据便签模式设置窗口层级
    func applyMode() {
        guard let window else { return }
        switch note.mode {
        case .floating:
            // 永远置顶: canJoinAllSpaces 跟随所有桌面, fullScreenAuxiliary
            // 让窗口作为全屏 app 的辅助窗口, 浮在全屏内容之上
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        case .normal:
            window.level = .normal
            window.collectionBehavior = [.managed]
        case .desktop:
            // 高于桌面图标层(否则会被 Finder 桌面拦截点击)、低于所有正常窗口
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        }
        dlog("窗口模式", "\(note.mode.displayName) level=\(window.level.rawValue)")
    }

    private func confirmDelete() {
        onDelete(note)
    }

    // 拖动/缩放后记住位置
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        note.frame = window.frame
        NoteStore.shared.scheduleSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if let f = window?.frame {
            note.frame = f
            NoteStore.shared.scheduleSave()
        }
    }
}
