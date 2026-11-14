import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()

    let store = ClipboardStore.shared
    let monitor = ClipboardMonitor()
    private let copyToast = CopyToastController()

    private var barController: BarWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var notedBlockedDirectPaste = false

    private(set) var previousApp: NSRunningApplication?
    private(set) var lastActiveApp: NSRunningApplication?

    var suppressAutoHide = false

    /// True while the bar still owns the system key window, even though SaiPaste
    /// itself is not active. The paste path has to wait this out.
    var barHoldsKeyWindow: Bool { barController?.holdsKeyWindow ?? false }

    /// When the search query last became empty via the keyboard. A bare
    /// Backspace deletes the selected clip, and the keystroke that clears the
    /// query must stay unambiguously separate from the keystroke that deletes.
    private var searchClearedAt: Date = .distantPast
    private static let deleteAfterSearchClearCooldown: TimeInterval = 0.6

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        monitor.start()

        HotKeyCenter.shared.onTrigger = { [weak self] in self?.toggleBar() }
        HotKeyCenter.shared.start()

        setupStatusItem()

        if Settings.shared.launchAtLogin { LaunchAtLogin.set(enabled: true) }

        if CommandLine.arguments.contains("--demo") {
            store.seedDemo()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showBar()
            }
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastActiveApp = app
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.forgetDeletions()
        store.saveNow()
    }

    /// Reopening from Finder, Spotlight, or the Dock surfaces the bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if barController?.isPresented != true {
            showBar()
        }
        return true
    }

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 SaiPaste", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 SaiPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // The Edit menu stays for the native search field's text editing.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let find = editMenu.addItem(withTitle: "查找…",
                                    action: #selector(NSTextView.performTextFinderAction(_:)),
                                    keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon(item)
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 SaiPaste   \(Settings.shared.hotkeyDisplay)",
                     action: #selector(menuOpen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SaiPaste", action: #selector(menuQuit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func menuOpen() { showBar() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func updateStatusItemIcon(_ item: NSStatusItem) {
        item.button?.image = statusIcon()
    }

    private func statusIcon() -> NSImage? {
        if let url = Bundle.module.url(forResource: "StatusIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            // The asset is 44 px (22 pt @2x). Left unspecified, NSImage reports
            // its pixel size as points and the status item draws it four times
            // too big next to a native menu bar extra.
            image.size = NSSize(width: 22, height: 22)
            return image
        }
        let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "SaiPaste")
        fallback?.isTemplate = true
        return fallback
    }

    func beginBarResize(at screenPoint: NSPoint) {
        barController?.beginBarResize(at: screenPoint)
    }

    func updateBarResize(at screenPoint: NSPoint) {
        barController?.updateBarResize(at: screenPoint)
    }

    func endBarResize(at screenPoint: NSPoint) {
        barController?.endBarResize(at: screenPoint)
    }

    func cancelBarResize() {
        barController?.cancelBarResize()
    }

    func adjustBarHeight(by delta: CGFloat) {
        barController?.adjustBarHeight(by: delta)
    }

    static func restart() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    func toggleBar() {
        BarLog.log.log("""
            hotkey: presented=\(self.barController?.isPresented ?? false, privacy: .public) \
            front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil", privacy: .public)
            """)
        if let bar = barController, bar.isPresented {
            hideBar()
        } else {
            showBar()
        }
    }

    /// A sleep cycle can strand the bar mid-transition and can drop the Carbon hotkey.
    @objc private func systemDidWake() {
        barController?.forceHide()
        stopKeyMonitor()
        HotKeyCenter.shared.reload()
    }

    /// Docking, undocking, and resolution changes can leave the bar sized for a
    /// screen that no longer exists.
    @objc private func screenParametersChanged() {
        barController?.forceHide()
        stopKeyMonitor()
    }

    func showBar() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, !isSaiPaste(front) {
            previousApp = front
            lastActiveApp = front
        }
        // The panel keeps its first responder across orderOut, so a field
        // left focused by a hide mid-search would otherwise own the next
        // presentation's keys.
        barController?.resignSearch()
        store.barInputMode = .cards
        store.searchText = ""
        store.prepareForBarPresentation()

        if barController == nil || barController?.window == nil {
            barController = BarWindowController()
        }
        barController?.show()
        startKeyMonitor()
    }

    func hideBar() {
        stopKeyMonitor()
        barController?.hide()
    }

    /// A click on a card takes keyboard focus away from the search field, so
    /// Backspace and Return act on the selection instead of editing the query.
    func focusCards() {
        barController?.resignSearch()
        store.barInputMode = .cards
    }

    func setBarSearchEditing(_ editing: Bool) {
        let mode: BarInputMode = editing ? .search : .cards
        guard store.barInputMode != mode else { return }
        store.barInputMode = mode
    }

    /// Routes every edit from the native search field through here instead
    /// of writing `store.searchText` directly, so the selection follows the
    /// filtered results as you type.
    func updateBarSearchText(_ text: String) {
        guard store.searchText != text else { return }
        store.searchText = text
        store.selectFirst()
    }

    func clearBarSearch() {
        let hadQuery = !store.searchText.isEmpty
        barController?.resignSearch()
        store.searchText = ""
        store.barInputMode = .cards
        if hadQuery { store.selectFirst(); searchClearedAt = Date() }
    }

    /// A click on the magnifying glass opens the query field. Without this the
    /// icon was decoration only, so the bar looked like it had no search at all.
    func beginBarSearch() {
        BarLog.log.log("beginBarSearch: mode=\(String(describing: self.store.barInputMode), privacy: .public) visible=\(self.barController?.window?.isVisible ?? false, privacy: .public)")
        store.barInputMode = .search
        if barController?.focusSearchAtEnd() == true { return }
        // The field can still be mid-layout right after the mode flips, so retry
        // a couple of times instead of giving up after one frame.
        for delay in [0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.store.barInputMode == .search else { return }
                if self.barController?.focusSearchAtEnd() == true { return }
            }
        }
    }

    func cancelBarSearchOrHide() {
        if !store.searchText.isEmpty {
            clearBarSearch()
        } else {
            hideBar()
        }
    }

    /// "始终以纯文本粘贴" decides the format for every paste path.
    private var pasteFormat: PasteFormat {
        Settings.shared.pasteAsPlainText ? .plainText : .original
    }

    func pasteSelected() {
        let items = store.selectedItems
        guard !items.isEmpty else { return }
        let target = pasteTarget
        hideBar()
        let previousChange = NSPasteboard.general.changeCount
        PasteService.paste(items, into: target, monitor: monitor, format: pasteFormat)
        if Settings.shared.promoteOnPaste, items.count == 1,
           NSPasteboard.general.changeCount != previousChange {
            store.promoteCopiedItem(items[0])
        }
    }

    /// The app that will receive a paste after the floating SaiPaste panel closes.
    /// `previousApp` is captured before the panel activates, while
    /// `lastActiveApp` covers menu-bar and reopen paths where it is unavailable.
    private var pasteTarget: NSRunningApplication? {
        [lastActiveApp, previousApp, NSWorkspace.shared.frontmostApplication]
            .compactMap { $0 }
            .first { !$0.isTerminated && !isSaiPaste($0) }
    }

    private func isSaiPaste(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return app.bundleIdentifier == bundleID
    }

    func pasteItem(_ item: ClipItem) {
        let target = pasteTarget
        hideBar()
        let previousChange = NSPasteboard.general.changeCount
        PasteService.paste([item], into: target, monitor: monitor, format: pasteFormat)
        if Settings.shared.promoteOnPaste, NSPasteboard.general.changeCount != previousChange {
            store.promoteCopiedItem(item)
        }
    }

    /// A direct paste that quietly falls back to a copy reads as "paste is
    /// broken". Say so, and offer the one click that fixes it.
    func noteBlockedDirectPaste() {
        if !notedBlockedDirectPaste {
            notedBlockedDirectPaste = true
            AccessibilityPermission.request(prompt: true)
        }
        copyToast.show(message: "未获得辅助功能权限，已复制到剪贴板",
                       symbol: "exclamationmark.triangle.fill",
                       actionTitle: "去授权",
                       action: AccessibilityPermission.openSettings,
                       linger: 6)
    }

    func deleteEffectiveSelection() {
        let targets = store.selectedItems
        guard !targets.isEmpty else { return }
        store.delete(items: targets)
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView()
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "SaiPaste 设置"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 520, height: 600))
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    /// Handles commands that only apply while the Paste Bar owns keyboard focus.
    func handleBarCommandShortcut(_ event: NSEvent) -> Bool {
        guard barController?.window?.isKeyWindow == true else { return false }

        let flags = event.modifierFlags
        guard flags.contains(.command), flags.contains(.shift),
              !flags.contains(.control), !flags.contains(.option) else { return false }

        if Int(event.keyCode) == kVK_ANSI_S {
            showSettings()
            return true
        }
        return false
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            BarLog.log.log("""
                raw key=\(event.keyCode, privacy: .public) \
                win=\(event.window == nil ? "nil" : "win", privacy: .public) \
                presented=\(self?.barController?.isPresented ?? false, privacy: .public) \
                appKey=\(NSApp.keyWindow != nil, privacy: .public) \
                resp=\(event.window?.firstResponder?.barLogName ?? "nil", privacy: .public)
                """)
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // While the app is still activating the panel cannot be key yet, and the
        // system hands the keystroke to NSApplication with no window attached.
        // Keep those events: dropping them is exactly "the first letter got eaten".
        guard let barWindow = barController?.window,
              barController?.isPresented == true,
              event.window == nil || event.window === barWindow else {
            BarLog.log.log("key dropped before handling: presented=\(self.barController?.isPresented ?? false, privacy: .public) win=\(event.window?.barLogName ?? "nil", privacy: .public)")
            return event
        }

        if barWindow.firstResponder is BarResizeHandleResponder { return event }

        if handleBarCommandShortcut(event) { return nil }

        let code = Int(event.keyCode)
        let flags = event.modifierFlags
        let cmd = flags.contains(.command)
        let ctrl = flags.contains(.control)
        let opt = flags.contains(.option)

        BarLog.log.log("""
            key code=\(code, privacy: .public) chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) \
            mode=\(String(describing: self.store.barInputMode), privacy: .public) \
            responder=\(barWindow.firstResponder?.barLogName ?? "nil", privacy: .public) \
            windowKey=\(barWindow.isKeyWindow, privacy: .public) appActive=\(NSApp.isActive, privacy: .public)
            """)

        // ⌘A selects every card, even while the search field is being edited.
        if cmd, !ctrl, !opt, !flags.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            store.selectAllVisible()
            return nil
        }

        // The native search field owns keys while it is editing: selection,
        // clipboard commands, deletion, and composed text all need real AppKit
        // text-editing behavior. Return and the arrows come back through the
        // field's delegate.
        if barController?.searchOwnsFirstResponder == true {
            return event
        }

        switch code {
        case kVK_Escape:
            if !store.multiSelectedIDs.isEmpty {
                store.clearMultiSelection()
            } else if !store.searchText.isEmpty {
                store.searchText = ""; store.selectFirst()
                searchClearedAt = Date()
            } else { hideBar() }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pasteSelected(); return nil
        case kVK_LeftArrow:
            store.moveSelection(by: -1)
            return nil
        case kVK_RightArrow:
            store.moveSelection(by: 1)
            return nil
        case kVK_UpArrow:
            store.moveSelection(by: -1); return nil
        case kVK_DownArrow:
            store.moveSelection(by: 1); return nil
        case kVK_Delete:
            // Backspace edits the query only while the search field is the
            // active input; after a card click it deletes the selection.
            if store.barInputMode == .search, !store.searchText.isEmpty {
                store.barInputMode = .search
                if barController?.focusSearchAtEnd() == true {
                    return event
                }
                store.searchText.removeLast(); store.selectFirst()
                if store.searchText.isEmpty { searchClearedAt = Date() }
                return nil
            }
            // A bare Backspace deletes the selection, but only as a deliberate,
            // separate keypress: auto-repeat is ignored, and a short cooldown
            // after the search empties separates "clear the query" from
            // "delete a clip".
            if !event.isARepeat,
               Date().timeIntervalSince(searchClearedAt) > Self.deleteAfterSearchClearCooldown {
                deleteEffectiveSelection()
            }
            return nil
        case kVK_ForwardDelete:
            deleteEffectiveSelection()
            return nil
        case kVK_ANSI_Z:
            if cmd, !ctrl, !opt, !flags.contains(.shift), store.undoLastDelete() { return nil }
        default:
            break
        }

        if isPrintableTextIntent(event) {
            store.barInputMode = .search
            if barController?.focusSearchAtEnd() == true {
                BarLog.log.log("""
                    typing: routed to field chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) \
                    ime=\(self.inputSourceID, privacy: .public)
                    """)
                return event
            }
            BarLog.log.log("""
                typing: focus failed, appended directly chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) \
                ime=\(self.inputSourceID, privacy: .public)
                """)
            if let chars = fallbackSearchCharacters(from: event) {
                store.searchText.append(chars)
                store.selectFirst()
            }
            return nil
        }
        return event
    }

    private var inputSourceID: String {
        NSTextInputContext.current?.selectedKeyboardInputSource ?? "none"
    }

    private func isPrintableTextIntent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard !flags.contains(.command),
              !flags.contains(.control),
              let chars = event.charactersIgnoringModifiers,
              !chars.isEmpty else { return false }
        return chars.unicodeScalars.contains {
            $0.value >= 0x20
                && $0.value != 0x7F
                && !(0xF700...0xF8FF).contains($0.value)
        }
    }

    private func fallbackSearchCharacters(from event: NSEvent) -> String? {
        let flags = event.modifierFlags
        guard !flags.contains(.command),
              !flags.contains(.control),
              let chars = event.characters,
              !chars.isEmpty,
              chars.unicodeScalars.allSatisfy({
                  $0.value >= 0x20
                      && $0.value != 0x7F
                      && !(0xF700...0xF8FF).contains($0.value)
              }) else { return nil }
        return chars
    }

}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
