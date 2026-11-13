import AppKit
import XCTest

@testable import SaiShot

/// Regression tests for the light history panel layout: the content must start
/// at the top of the scroll view (not bottom-anchored) and thumbnails must wrap
/// into rows instead of running off the right edge.
final class HistoryPanelLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.set(true, forKey: "historyCacheEnabled")
    }

    func testContentStartsAtTopAndThumbnailsWrap() throws {
        let controller = HistoryPanelController(onEditEntry: { _ in })
        controller.toggleFromUserRequest()
        defer { controller.close() }

        guard let window = NSApplication.shared.windows.first(where: { $0.title == L10n.historyMenu }),
              let content = window.contentView
        else {
            XCTFail("history panel did not open")
            return
        }

        content.layoutSubtreeIfNeeded()

        if let path = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT"], !path.isEmpty {
            Self.writeSnapshot(of: content, to: path)
        }

        guard let scrollView = Self.firstScrollView(in: content),
              let document = scrollView.documentView
        else {
            XCTFail("history panel has no scroll view")
            return
        }

        XCTAssertTrue(document.isFlipped, "document view must be flipped so content anchors at the top")

        let buttons = Self.thumbnailButtons(in: document)
        guard !buttons.isEmpty else { return }  // no screenshots on disk: nothing to lay out

        let frames = buttons.map { button -> NSRect in
            button.convert(button.bounds, to: document)
        }

        let topMost = frames.map(\.minY).min() ?? 0
        XCTAssertLessThan(topMost, 120, "first row should sit near the top, not at the bottom of the panel")

        let distinctRows = Set(frames.map { Int($0.minY.rounded()) })
        XCTAssertGreaterThan(distinctRows.count, 1, "\(buttons.count) thumbnails should wrap into more than one row")

        let rightMost = frames.map(\.maxX).max() ?? 0
        XCTAssertLessThanOrEqual(
            rightMost,
            document.bounds.width + 1,
            "thumbnails must stay inside the document width so nothing is clipped"
        )
    }

    private static func writeSnapshot(of view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    private static func thumbnailButtons(in view: NSView) -> [NSButton] {
        var result: [NSButton] = []
        for subview in view.subviews {
            if let button = subview as? NSButton, button.accessibilityLabel()?.hasSuffix(".png") == true {
                result.append(button)
            }
            result.append(contentsOf: thumbnailButtons(in: subview))
        }
        return result
    }
}
