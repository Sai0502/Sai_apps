import AppKit
import XCTest
@testable import SaiPaste

/// Covers the fork's core promises: ⌘A selects everything, Shift+click keeps
/// the anchor, Backspace deletes the whole selection as one undoable step, and
/// a multi-clip paste merges textual clips with a blank line between them.
@MainActor
final class SelectionAndPasteTests: XCTestCase {
    private var pasteboardSnapshot: [(NSPasteboard.PasteboardType, Data)] = []

    override func setUp() async throws {
        ClipboardStore.shared.clearHistory()
        ClipboardStore.shared.searchText = ""
        let pb = NSPasteboard.general
        pasteboardSnapshot = (pb.types ?? []).compactMap { type in
            pb.data(forType: type).map { (type, $0) }
        }
    }

    override func tearDown() async throws {
        ClipboardStore.shared.clearHistory()
        ClipboardStore.shared.searchText = ""
        let pb = NSPasteboard.general
        pb.clearContents()
        for (type, data) in pasteboardSnapshot { pb.setData(data, forType: type) }
    }

    /// Seeds history so the on-screen order is exactly `texts`, newest first.
    private func load(_ texts: [String]) {
        for text in texts.reversed() {
            ClipboardStore.shared.addCaptured(ClipItem(type: .text, text: text))
        }
    }

    func testSelectAllVisibleSelectsEveryClip() {
        load(["a", "b", "c", "d", "e"])
        let store = ClipboardStore.shared
        store.selectAllVisible()

        XCTAssertEqual(store.effectiveSelectionIDs.count, 5)
        XCTAssertEqual(store.selectedItems.map(\.text), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(store.selectedID, store.visibleItems.first?.id,
                       "cursor stays on the first card so the strip does not jump")
        XCTAssertTrue(store.isSelected(store.visibleItems[4].id))
    }

    func testSelectAllRespectsTheSearchFilter() {
        load(["alpha", "beta", "alphabet"])
        let store = ClipboardStore.shared
        store.searchText = "alpha"
        store.selectAllVisible()

        XCTAssertEqual(store.effectiveSelectionIDs.count, 2)
        XCTAssertEqual(store.selectedItems.map(\.text), ["alpha", "alphabet"])
    }

    func testShiftExtendKeepsTheAnchorAndSelectsTheInclusiveRange() {
        load(["a", "b", "c", "d"])
        let store = ClipboardStore.shared
        let items = store.visibleItems
        store.select(items[0].id)
        store.extendSelection(to: items[2].id)

        XCTAssertEqual(store.effectiveSelectionIDs, Set(items[0...2].map(\.id)))
        XCTAssertEqual(store.selectedID, items[2].id, "cursor follows the click")

        // Extending again from the same anchor shrinks the range.
        store.extendSelection(to: items[1].id)
        XCTAssertEqual(store.effectiveSelectionIDs, Set(items[0...1].map(\.id)))
    }

    func testTypingASearchClearsTheMultiSelection() {
        load(["a", "b", "c"])
        let store = ClipboardStore.shared
        store.selectAllVisible()
        XCTAssertEqual(store.effectiveSelectionIDs.count, 3)

        store.searchText = "b"
        XCTAssertTrue(store.multiSelectedIDs.isEmpty)
        XCTAssertEqual(store.effectiveSelectionIDs.count, 1)
    }

    func testBulkDeleteRestoresTheWholeSelectionInPlaceWithOneUndo() {
        load(["a", "b", "c", "d"])
        let store = ClipboardStore.shared
        let items = store.visibleItems
        store.selectAllVisible()

        store.delete(items: store.selectedItems)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(store.hasUndoableDeletion)

        XCTAssertTrue(store.undoLastDelete())
        XCTAssertEqual(store.history.map(\.text), items.map(\.text),
                       "undo puts every clip back at its original position")
        XCTAssertFalse(store.hasUndoableDeletion)
    }

    func testDeletingTheSelectionLeavesTheRestIntactAndKeepsACursor() {
        load(["a", "b", "c", "d"])
        let store = ClipboardStore.shared
        let items = store.visibleItems
        store.select(items[1].id)
        store.extendSelection(to: items[2].id)
        store.delete(items: store.selectedItems)

        XCTAssertEqual(store.history.map(\.text), ["a", "d"])
        XCTAssertNotNil(store.selectedID, "a cursor survives the delete")
        XCTAssertTrue(store.multiSelectedIDs.isEmpty)
    }

    func testMovingTheSelectionCollapsesItToOneCard() {
        load(["a", "b", "c"])
        let store = ClipboardStore.shared
        store.selectAllVisible()
        store.moveSelection(by: 1)

        XCTAssertTrue(store.multiSelectedIDs.isEmpty)
        XCTAssertEqual(store.selectedID, store.visibleItems[1].id)
    }

    func testTextualSelectionMergesIntoOneBlockWithABlankLine() {
        let a = ClipItem(type: .text, text: "first")
        let b = ClipItem(type: .link, text: "https://example.com")
        let c = ClipItem(type: .richText, text: "third")
        PasteService.paste([a, b, c], into: nil, monitor: ClipboardMonitor())

        XCTAssertEqual(NSPasteboard.general.string(forType: .string),
                       "first\n\nhttps://example.com\n\nthird")
    }

    func testFileSelectionBecomesOneMultiFilePaste() {
        let a = ClipItem(type: .file, text: "one.txt", fileURLs: ["file:///tmp/one.txt"])
        let b = ClipItem(type: .file, text: "two.txt", fileURLs: ["file:///tmp/two.txt"])
        PasteService.paste([a, b], into: nil, monitor: ClipboardMonitor())

        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(urls?.map(\.lastPathComponent), ["one.txt", "two.txt"])
    }

    func testPlainTextPasteStripsTheLinkFormat() {
        let a = ClipItem(type: .text, text: "plain one")
        let b = ClipItem(type: .text, text: "plain two")
        PasteService.paste([a, b], into: nil, monitor: ClipboardMonitor(), format: .plainText)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "plain one\n\nplain two")
    }
}
