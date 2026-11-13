import AppKit
import SwiftUI

/// StickyNotes（便签）模块：与其他模块同级，负责便签窗口的生命周期与菜单入口。
/// 数据存储在 ~/Library/Application Support/SwissKnife/StickyNotes/
@MainActor
final class StickyNotesModule: NSObject {
    static let shared = StickyNotesModule()

    private var controllers: [UUID: NoteWindowController] = [:]
    private var historyWindow: NSWindow?

    private override init() {
        super.init()
    }

    // MARK: - 生命周期

    func start() {
        dlog("启动", "StickyNotes 模块已加载")
        NoteStore.shared.load()
        if NoteStore.shared.notes.isEmpty {
            createNote()
        } else {
            NoteStore.shared.notes.forEach(showWindow)
        }
    }

    func stop() {
        NoteStore.shared.saveNow()
    }

    // MARK: - 菜单

    /// 追加 StickyNotes 分组菜单项：标题行 + 新文字便签 / 历史便签
    func appendMenuItems(to menu: NSMenu) {
        let line = NSMenuItem(title: "StickyNotes", action: nil, keyEquivalent: "")
        line.isEnabled = false
        menu.addItem(line)

        let newItem = NSMenuItem(title: "    新文字便签", action: #selector(newNote), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)

        let historyItem = NSMenuItem(title: "    历史便签", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)
    }

    // MARK: - 调试快照

    func debugSummary() -> String {
        let notes = NoteStore.shared.notes.count
        let archived = NoteStore.shared.archived.count
        return "便签: \(notes) 张在屏 | 历史: \(archived) 条"
    }

    // MARK: - 便签管理

    @objc private func newNote() { createNote() }

    @discardableResult
    func createNote(text: String = "", theme: NoteTheme? = nil,
                            mode: NoteMode = .floating,
                            highlights: [TextHighlight] = [],
                            bolds: [TextHighlight] = [],
                            images: [String: NoteImage] = [:]) -> Note {
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(
            x: screen.midX - 140 + cascade,
            y: screen.midY - 20 - cascade,
            width: 280, height: 280)

        // 未指定颜色时顺延取色, 避免全是黄色
        let usedThemes = NoteStore.shared.notes.map(\.theme)
        let nextTheme = theme
            ?? NoteTheme.allCases.first { !usedThemes.contains($0) }
            ?? NoteTheme.allCases[NoteStore.shared.notes.count % NoteTheme.allCases.count]

        let note = Note(text: text, theme: nextTheme, mode: mode,
                        highlights: highlights, bolds: bolds,
                        images: images, frame: frame)
        NoteStore.shared.add(note)
        showWindow(note)
        dlog("新建便签", "id=\(note.id.uuidString.prefix(8)) 主题=\(note.theme.displayName)")
        return note
    }

    private func showWindow(_ note: Note) {
        if note.frame.width < 50 {
            note.frame = CGRect(x: 200, y: 200, width: 280, height: 280)
        }
        let controller = NoteWindowController(
            note: note,
            onDelete: { [weak self] n in self?.delete(n) },
            onNewNote: { [weak self] in self?.createNote() }
        )
        controller.window?.setFrame(note.frame, display: true)
        controllers[note.id] = controller
        // 淡入出现
        controller.window?.alphaValue = 0
        controller.window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            controller.window?.animator().alphaValue = 1
        }
        if note.mode != .desktop {
            controller.window?.makeKey()
        }
    }

    private func delete(_ note: Note) {
        dlog("删除便签", "id=\(note.id.uuidString.prefix(8)) 已归档")
        controllers[note.id]?.window?.orderOut(nil)
        controllers[note.id] = nil
        NoteStore.shared.archive(note)   // 有内容的便签先归档进历史
        NoteStore.shared.remove(note)
    }

    // MARK: - 历史便签

    @objc func showHistory() {
        NSApp.activateBestEffort()
        if historyWindow == nil {
            let view = HistoryView(store: NoteStore.shared) { [weak self] item in
                self?.restore(item)
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            win.title = "历史便签"
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.center()
            historyWindow = win
        }
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    /// 把历史记录恢复成一张新便签
    private func restore(_ item: ArchivedNote) {
        guard let archived = NoteStore.shared.unarchive(item.id) else { return }
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let note = Note(
            text: archived.text, theme: archived.theme,
            highlights: archived.highlights,
            bolds: archived.bolds,
            images: archived.images,
            lineCreatedAt: archived.lineCreatedAt,
            frame: CGRect(x: screen.midX - 140 + cascade, y: screen.midY - 20 - cascade,
                          width: 280, height: 280))
        NoteStore.shared.add(note)
        showWindow(note)
        dlog("恢复便签", "id=\(item.id.uuidString.prefix(8))")
    }
}
