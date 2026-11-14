import AppKit
import Carbon.HIToolbox

/// How a clip's content is written to the pasteboard when pasting.
enum PasteFormat {
    /// The clip exactly as captured.
    case original
    /// Text only, all formatting removed.
    case plainText
}

@MainActor
enum PasteService {
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    private static let packagedBundleID = "com.greycorelabs.saipaste"
    /// Delay between successive pastes when the selection cannot be merged.
    private static let sequenceDelay: TimeInterval = 0.31

    private static func markSource(of item: ClipItem, on pasteboard: NSPasteboard) {
        let source = item.sourceBundleID ?? Bundle.main.bundleIdentifier ?? packagedBundleID
        pasteboard.setString(source, forType: sourceType)
    }

    @discardableResult
    static func copy(_ item: ClipItem,
                     format: PasteFormat = .original,
                     to pasteboard: NSPasteboard = .general) -> Int {
        if format == .plainText, let text = item.plainText {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            markSource(of: item, on: pasteboard)
            return pasteboard.changeCount
        }
        if item.type == .image {
            guard let img = ClipboardStore.shared.loadImage(for: item) else {
                return pasteboard.changeCount
            }
            pasteboard.clearContents()
            pasteboard.writeObjects([img])
            markSource(of: item, on: pasteboard)
            return pasteboard.changeCount
        }
        pasteboard.clearContents()
        switch item.type {
        case .image:
            break
        case .file:
            let urls = item.fileURLs.compactMap { URL(string: $0) }
            if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .color:
            if let hex = item.colorHex, let c = NSColor(hex: hex) {
                pasteboard.writeObjects([c])
                pasteboard.setString(hex, forType: .string)
            }
        case .richText:
            if let rtf = item.rtfData { pasteboard.setData(rtf, forType: .rtf) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .text, .link:
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        }
        markSource(of: item, on: pasteboard)
        return pasteboard.changeCount
    }

    /// Pastes one clip, or a whole selection.
    static func paste(_ items: [ClipItem],
                      into targetApp: NSRunningApplication?,
                      monitor: ClipboardMonitor,
                      format: PasteFormat = .original) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            let change = copy(items[0], format: format)
            monitor.suppressUntilChangeCount = change
            playPasteSound()
            guard let target = targetApp, !target.isTerminated else { return }
            guard AccessibilityPermission.isTrusted else {
                AppController.shared.noteBlockedDirectPaste()
                return
            }
            target.activate()
            waitForFrontmost(target, attempts: 20) { sendCommandV() }
            return
        }

        if let change = merge(items, format: format) {
            monitor.suppressUntilChangeCount = change
            playPasteSound()
            guard let target = targetApp, !target.isTerminated else { return }
            guard AccessibilityPermission.isTrusted else {
                AppController.shared.noteBlockedDirectPaste()
                return
            }
            target.activate()
            waitForFrontmost(target, attempts: 20) { sendCommandV() }
            return
        }

        // Mixed types or images: paste each clip in on-screen order.
        playPasteSound()
        pasteSequentially(items, index: 0, target: targetApp, monitor: monitor, format: format)
    }

    /// Text joins into one block (blank line between clips), files join into
    /// one multi-file paste; anything else is pasted card by card.
    private static func merge(_ items: [ClipItem], format: PasteFormat) -> Int? {
        let pasteboard = NSPasteboard.general
        if items.allSatisfy({ $0.type == .file }) {
            let urls = items.flatMap(\.fileURLs).compactMap { URL(string: $0) }
            guard !urls.isEmpty else { return nil }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            markSource(of: items[0], on: pasteboard)
            return pasteboard.changeCount
        }
        let textual: Set<ClipType> = [.text, .richText, .link]
        guard items.allSatisfy({ textual.contains($0.type) }) else { return nil }
        let joined = items.compactMap(\.plainText).joined(separator: "\n\n")
        guard !joined.isEmpty else { return nil }
        pasteboard.clearContents()
        pasteboard.setString(joined, forType: .string)
        markSource(of: items[0], on: pasteboard)
        return pasteboard.changeCount
    }

    private static func pasteSequentially(_ items: [ClipItem],
                                          index: Int,
                                          target: NSRunningApplication?,
                                          monitor: ClipboardMonitor,
                                          format: PasteFormat) {
        guard index < items.count else { return }
        // Copy before the capability checks: without Accessibility the first
        // clip still lands on the clipboard, exactly like a single paste.
        let item = items[index]
        let change = copy(item, format: format)
        monitor.suppressUntilChangeCount = change
        guard let target, !target.isTerminated else { return }
        guard AccessibilityPermission.isTrusted else {
            AppController.shared.noteBlockedDirectPaste()
            return
        }
        target.activate()
        waitForFrontmost(target, attempts: 20) {
            sendCommandV()
            guard index + 1 < items.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + sequenceDelay) {
                pasteSequentially(items, index: index + 1, target: target, monitor: monitor, format: format)
            }
        }
    }

    private static func playPasteSound() {
        guard Settings.shared.playSound else { return }
        NSSound(named: "Pop")?.play()
    }

    private static func waitForFrontmost(_ app: NSRunningApplication, attempts: Int,
                                         then action: @escaping @MainActor () -> Void) {
        guard attempts > 0, !app.isTerminated else { return }
        // The target being frontmost is not sufficient. A nonactivating panel can
        // still be the key window while SaiPaste is not frontmost, and a ⌘V posted
        // then lands in SaiPaste. Wait for the bar to really let go of key.
        let targetIsFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        let keyReleased = !AppController.shared.barHoldsKeyWindow
        if targetIsFront && keyReleased {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000)
                BarLog.log.log("paste: front=\(app.localizedName ?? "?", privacy: .public) keyReleased=\(keyReleased, privacy: .public)")
                action()
            }
            return
        }
        if attempts == 1 {
            BarLog.log.log("""
                paste: gave up waiting front=\(targetIsFront, privacy: .public) \
                keyReleased=\(keyReleased, privacy: .public) \
                keyWindow=\(NSApp.keyWindow?.barLogName ?? "nil", privacy: .public)
                """)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            waitForFrontmost(app, attempts: attempts - 1, then: action)
        }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// The Accessibility grant that lets SaiPaste synthesize ⌘V.
@MainActor
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Passing `prompt: true` also registers SaiPaste in the system's Accessibility
    /// list, which is what makes it appear there for the user to switch on.
    @discardableResult
    static func request(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
