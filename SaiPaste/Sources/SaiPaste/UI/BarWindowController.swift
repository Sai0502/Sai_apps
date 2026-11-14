import AppKit
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if AppController.shared.handleBarCommandShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class BarWindowController: NSWindowController, NSWindowDelegate {

    /// Where the bar is in its show/hide cycle.
    ///
    /// This is the authoritative answer to "is the bar up?". `NSWindow.isVisible` used
    /// to serve that role, but it only returns to false inside an animation completion
    /// handler, and AppKit drops those handlers when a later animation supersedes them
    /// on the same property. One missed `orderOut` left the panel permanently
    /// "visible", so every hotkey press routed to `hide()` and the bar never came back
    /// until the app was relaunched. That is issue #64.
    private enum Phase: Equatable {
        case hidden
        case showing(Int)
        case shown
        case hiding(Int)
    }

    private var phase: Phase = .hidden
    /// When the bar last finished appearing. A key loss right after this is the
    /// system reshuffling focus, not the user clicking somewhere else.
    private var settledAt: Date?
    private var epoch = 0
    private let searchBridge = BarSearchFieldBridge()
    private var targetVisibleFrame: NSRect?
    private var resizeSession: BarResizeSession?

    /// True while the bar is up or on its way up. `AppController.toggleBar` asks this
    /// instead of `window.isVisible`.
    var isPresented: Bool {
        switch phase {
        case .showing, .shown: return true
        case .hidden, .hiding: return false
        }
    }

    private static let showDuration: TimeInterval = 0.22
    private static let hideDuration: TimeInterval = 0.16

    private static var contentBottomExtension: CGFloat {
        if #available(macOS 26.0, *) { return Theme.cornerRadius }
        return 0
    }

    init() {
        let panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 360),
            // A nonactivating panel becomes key without activating SaiPaste. That
            // matters over a fullscreen Space: activating an LSUIElement app that
            // has no window there makes WindowServer move the panel to a desktop
            // Space, so the bar surfaced behind the desktop instead of the
            // fullscreen app. This panel therefore never calls activate(); the
            // local key monitor in AppController routes the first keystroke.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        // A click or a command shortcut must reach the panel even though it is
        // presented without activating the app.
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        // Without this a stray close() would deallocate the panel and leave `window`
        // nil, which is another way to never show the bar again.
        panel.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: BarView(searchBridge: searchBridge))
        if #available(macOS 26.0, *) {
            let glassContent = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            glassContent.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: glassContent.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: glassContent.trailingAnchor),
                content.topAnchor.constraint(equalTo: glassContent.topAnchor),
                content.bottomAnchor.constraint(equalTo: glassContent.bottomAnchor,
                                                constant: -Theme.cornerRadius),
            ])

            let glass = NSGlassEffectView()
            glass.contentView = glassContent
            glass.cornerRadius = Theme.cornerRadius
            glass.tintColor = NSColor.black.withAlphaComponent(0.12)
            glass.style = .regular
            panel.contentView = glass
            panel.hasShadow = false
        } else {
            panel.contentView = content
        }
        super.init(window: panel)
        panel.delegate = self
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureKey() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// The screen the bar should slide up from: the one under the pointer.
    ///
    /// `NSRect.contains` excludes a rect's max edges, so a pointer sitting exactly on
    /// the boundary between two displays matches none of them. Displays of differing
    /// sizes also leave unreachable gaps in the global coordinate space. Both cases
    /// used to fall through to `NSScreen.main`, which is the screen holding the *key
    /// window* — not the one the pointer is on — so the bar surfaced on the wrong
    /// display. Hit-test with `NSMouseInRect`, then fall back to the nearest screen.
    private static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return hit
        }
        return NSScreen.screens.min { a, b in
            distanceSquared(from: a.frame, to: mouse) < distanceSquared(from: b.frame, to: mouse)
        }
    }

    private static func distanceSquared(from rect: NSRect, to point: NSPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// What the bar was competing with when it appeared, for the log only.
    ///
    /// The fullscreen flag is the one that matters: the bar could not surface on a
    /// fullscreen Space before, so a recurrence needs to answer "was a fullscreen
    /// window in front" from the log alone.
    private static func presentationContext() -> String {
        guard let front = NSWorkspace.shared.frontmostApplication else { return "nil" }
        let name = front.localizedName ?? "?"
        return "\(name)(fullscreen=\(isFullscreen(front)))"
    }

    private static func isFullscreen(_ app: NSRunningApplication) -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return false }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowRef as! AXUIElement, "AXFullScreen" as CFString, &valueRef) == .success,
              let value = valueRef as? Bool else { return false }
        return value
    }

    /// Bumps the transition counter so any completion still in flight becomes stale.
    private func beginTransition() -> Int {
        epoch &+= 1
        return epoch
    }

    /// Runs `body` exactly once for the transition identified by `token`, and never for
    /// a transition that has already been superseded.
    ///
    /// Both the animation completion handler and a backstop timer call through here.
    /// The timer is what actually guarantees progress - AppKit drops completion handlers
    /// when a later animation replaces them, and relying on one to run was the original
    /// bug. Bumping `epoch` on settle makes the second caller for the same token a no-op.
    private func settle(_ token: Int, _ body: () -> Void) {
        guard epoch == token else { return }
        epoch &+= 1
        body()
    }

    func show() {
        guard let panel = window else { return }
        guard let screen = Self.targetScreen() else { return }
        // Clicking anywhere else always hides the bar; the panel level is what
        // makes that resign-key hand-off immediate.
        panel.level = .modalPanel
        let vf = screen.visibleFrame
        let onScreen = BarResizeGeometry.panelFrame(
            for: Settings.shared.barHeight,
            in: vf
        )
        let height = onScreen.height
        targetVisibleFrame = vf
        resizeSession = nil

        // The panel stays parked at its final frame and the content slides up *inside*
        // it. Animating the window frame itself is not safe on multi-display setups:
        // the old staging rect (vf.minY - height) is only genuinely off-screen when
        // nothing sits below the target display. With displays stacked vertically it
        // lands on the neighbouring screen, so the bar appeared there in full and then
        // flew across the bezel. A view clipped to the window can never escape it.
        panel.setFrame(onScreen, display: false)
        guard let content = panel.contentView else { return }
        let bottomExtension = Self.contentBottomExtension
        let contentHeight = height + bottomExtension
        content.autoresizingMask = []
        content.frame = NSRect(x: 0, y: -contentHeight,
                               width: onScreen.width, height: contentHeight)

        let token = beginTransition()
        phase = .showing(token)
        BarLog.log.log("""
            show: screen=\(NSStringFromRect(vf), privacy: .public) \
            front=\(Self.presentationContext(), privacy: .public)
            """)

        // Present without activating the app. orderFrontRegardless brings the
        // panel up while SaiPaste is not frontmost, and makeKey takes keyboard
        // focus synchronously, so the first keystroke lands in the bar. Neither
        // call changes the active Space, which is what keeps the bar on a
        // fullscreen Space instead of sending it to the desktop.
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak panel] in
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
            BarLog.log.log("focus: app=\(NSApp.isActive, privacy: .public) run=\(NSRunningApplication.current.isActive, privacy: .public) key=\(panel?.isKeyWindow ?? false, privacy: .public) front=\(front, privacy: .public)")
        }
        // A nonactivating panel still has to win the key window from whatever the
        // previous app holds, and that is not always immediate. Re-assert key
        // while the slide-up runs so the bar is typeable almost at once.
        for delay in [0.05, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak panel] in
                guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                panel.makeKey()
                BarLog.log.log("rekey at +\(delay, privacy: .public)s key=\(panel.isKeyWindow, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
            }
        }
        BarLog.log.log("""
            show: appActive=\(NSApp.isActive, privacy: .public) \
            windowKey=\(panel.isKeyWindow, privacy: .public) \
            appPolicy=\(NSApp.activationPolicy().rawValue, privacy: .public)
            """)
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.settle(token) {
                self.phase = .shown
                self.settledAt = Date()
                // The panel can lose key focus while it is still animating up, and
                // windowDidResignKey ignores that because the bar is not .shown yet.
                // Catch it here so the bar does not sit on screen unfocused forever.
                BarLog.log.log("show settle: key=\(panel.isKeyWindow, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
                if !panel.isKeyWindow { self.ensureKey() }
                if panel.isVisible, !panel.isKeyWindow, !AppController.shared.suppressAutoHide {
                    // Give key acquisition one more beat before giving up on the bar.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak panel, weak self] in
                        guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                        BarLog.log.log("settle fallback hide: key=false active=\(NSApp.isActive, privacy: .public)")
                        self?.ensureKey()
                        guard panel.isVisible, !panel.isKeyWindow else { return }
                        AppController.shared.hideBar()
                    }
                }
            }
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.showDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            content.animator().frame = BarResizeGeometry.presentedContentFrame(
                panelSize: onScreen.size,
                bottomExtension: bottomExtension
            )
        }, completionHandler: { DispatchQueue.main.async(execute: finish) })
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDuration + 0.05, execute: finish)
    }

    /// Re-assert key focus on the nonactivating panel. Cheap enough to call from
    /// several places, and the panel is the only window that may be key here.
    /// True while the panel still holds the system key window.
    ///
    /// A nonactivating panel can be the key window while SaiPaste is not the
    /// frontmost app, and it keeps that status until `orderOut`. Anything typed
    /// during that window — including the ⌘V the paste path synthesizes — lands
    /// in SaiPaste instead of the app the user meant to paste into.
    var holdsKeyWindow: Bool {
        window?.isKeyWindow ?? false
    }

    private func ensureKey() {
        guard let panel = window, panel.isVisible, isPresented, !panel.isKeyWindow else { return }
        panel.makeKey()

        BarLog.log.log("ensureKey: key=\(panel.isKeyWindow, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
    }

    func hide() {
        guard let panel = window, let content = panel.contentView else { return }
        guard isPresented else { return }
        cancelBarResize()

        let token = beginTransition()
        phase = .hiding(token)
        // Relinquish key now instead of waiting for orderOut. A nonactivating
        // panel keeps the system key window until it leaves the screen, and the
        // paste path posts ⌘V right after hiding — if the panel still held key,
        // that synthetic keystroke would land back in SaiPaste and the app would
        // only beep. WindowDidResignKey sees phase == .hiding above and stays out
        // of the way, so this cannot recurse into a second hide.
        if panel.isKeyWindow {
            panel.resignKey()
            BarLog.log.log("hide: resigned key key=\(panel.isKeyWindow, privacy: .public)")
        }
        let down = NSRect(x: 0, y: -content.frame.height,
                          width: content.frame.width, height: content.frame.height)

        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.settle(token) {
                panel.orderOut(nil)
                self.phase = .hidden
            }
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.hideDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            content.animator().frame = down
        }, completionHandler: { DispatchQueue.main.async(execute: finish) })
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDuration + 0.05, execute: finish)
    }

    /// Drops the bar with no animation and no completion handler to depend on.
    /// Used after sleep or a display change, where an in-flight transition can be
    /// left stranded on a screen that no longer exists.
    func forceHide() {
        resizeSession = nil
        _ = beginTransition()
        phase = .hidden
        window?.orderOut(nil)
    }

    var searchOwnsFirstResponder: Bool {
        searchBridge.ownsFirstResponder(in: window)
    }

    @discardableResult
    func focusSearchAtEnd() -> Bool {
        searchBridge.focusAtEnd()
    }

    func resignSearch() {
        searchBridge.resign()
    }

    func beginBarResize(at screenPoint: NSPoint) {
        guard phase == .shown,
              resizeSession == nil,
              let panel = window,
              let visibleFrame = targetVisibleFrame else { return }
        resizeSession = BarResizeSession(
            initialPanelHeight: panel.frame.height,
            initialScreenY: screenPoint.y,
            visibleFrame: visibleFrame
        )
    }

    func updateBarResize(at screenPoint: NSPoint) {
        guard phase == .shown, let resizeSession else { return }
        applyResizeFrame(resizeSession.frame(atScreenY: screenPoint.y))
    }

    func endBarResize(at screenPoint: NSPoint) {
        guard phase == .shown, let resizeSession else { return }
        let frame = resizeSession.frame(atScreenY: screenPoint.y)
        let persistedHeight = resizeSession.finalPersistedHeight(atScreenY: screenPoint.y)
        self.resizeSession = nil
        applyResizeFrame(frame)
        Settings.shared.barHeight = persistedHeight
    }

    func cancelBarResize() {
        guard let resizeSession else { return }
        self.resizeSession = nil
        guard phase == .shown else { return }
        applyResizeFrame(resizeSession.cancelledFrame)
    }

    func adjustBarHeight(by delta: CGFloat) {
        guard phase == .shown,
              resizeSession == nil,
              let panel = window,
              let visibleFrame = targetVisibleFrame else { return }
        let requested = Double(panel.frame.height + delta)
        let frame = BarResizeGeometry.panelFrame(for: requested, in: visibleFrame)
        applyResizeFrame(frame)
        Settings.shared.barHeight = Double(frame.height)
    }

    private func applyResizeFrame(_ frame: NSRect) {
        guard let panel = window, let content = panel.contentView,
              frame.width > 0, frame.height > 0 else { return }
        panel.setFrame(frame, display: true)
        content.frame = BarResizeGeometry.presentedContentFrame(
            panelSize: frame.size,
            bottomExtension: Self.contentBottomExtension
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        let newKey = NSApp.keyWindow?.barLogName ?? "nil"
        let sinceSettle = settledAt.map { Date().timeIntervalSince($0) } ?? -1
        BarLog.log.log("""
            resignKey: newKey=\(newKey, privacy: .public) \
            appActive=\(NSApp.isActive, privacy: .public) \
            phase=\(String(describing: self.phase), privacy: .public) \
            sinceSettle=\(sinceSettle, privacy: .public)
            """)
        guard phase == .shown,
              !AppController.shared.suppressAutoHide else { return }
        // Focus can bounce once right after the panel takes key — a Space change,
        // another app's window finishing its own transition, the status menu
        // opening. Hiding on that made the bar flicker away, which reads as "the
        // hotkey did nothing". Give the system one grace period to hand key back
        // and only hide if it really is gone.
        if let settledAt, Date().timeIntervalSince(settledAt) < 0.4 {
            BarLog.log.log("resignKey: inside settle grace, re-checking")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, let panel = self.window, panel.isVisible,
                      self.phase == .shown, !panel.isKeyWindow,
                      !AppController.shared.suppressAutoHide else { return }
                BarLog.log.log("resignKey: key not restored, hiding")
                AppController.shared.hideBar()
            }
            return
        }
        AppController.shared.hideBar()
    }
}
