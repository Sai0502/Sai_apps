import AppKit
import SwiftUI

/// AppKit click handling for SwiftUI content.
///
/// Two reasons this exists instead of `.onTapGesture`:
/// 1. Chaining `.onTapGesture(count: 2)` in front of a single tap makes SwiftUI
///    hold the single tap until the system double-click interval elapses
///    (~350 ms), which reads as a lag when selecting a card.
///    `NSEvent.clickCount` reports the same semantics with no arbitration.
/// 2. SwiftUI views do not opt into first-mouse acceptance, so the click that
///    wakes an inactive panel can be swallowed before any action runs.
struct ClickCatcher: NSViewRepresentable {
    /// (clickCount, modifierFlags) — the caller decides single vs double vs shift.
    let onClick: (_ clickCount: Int, _ modifiers: NSEvent.ModifierFlags) -> Void
    var onHoverChange: ((Bool) -> Void)?

    final class ClickView: NSView {
        var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
        var onHoverChange: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override var isOpaque: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            return bounds.contains(local) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            onClick?(event.clickCount, event.modifierFlags)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
        override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
    }

    func makeNSView(context: Context) -> NSView {
        let view = ClickView()
        view.onClick = onClick
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ClickView else { return }
        view.onClick = onClick
        view.onHoverChange = onHoverChange
    }
}
