import XCTest
@testable import SaiPaste

final class ClipUndoStackTests: XCTestCase {
    private func placement(_ item: ClipItem, index: Int,
                           before predecessor: ClipItem? = nil,
                           after successor: ClipItem? = nil) -> ClipPlacement {
        ClipPlacement(index: index, item: item,
                      predecessorID: predecessor?.id, successorID: successor?.id)
    }

    func testBulkDeletionComesBackAsOneEntryNewestFirst() {
        var stack = ClipUndoStack()
        let a = ClipItem(type: .text, text: "a")
        let b = ClipItem(type: .text, text: "b")
        let c = ClipItem(type: .text, text: "c")
        _ = stack.push([placement(a, index: 0)])
        _ = stack.push([placement(b, index: 1), placement(c, index: 2)])

        XCTAssertEqual(stack.pop()?.placements.map(\.item.id), [b.id, c.id])
        XCTAssertEqual(stack.pop()?.placements.first?.item.id, a.id)
        XCTAssertNil(stack.pop())
        XCTAssertTrue(stack.isEmpty)
    }

    func testCapDropsOldestDeletionsAndHandsThemBack() {
        var stack = ClipUndoStack()
        var dropped: [ClipDeletion] = []
        for index in 0..<(ClipUndoStack.limit + 2) {
            let item = ClipItem(type: .image, imageFileName: "shot-\(index).png")
            dropped += stack.push([placement(item, index: 0)])
        }
        XCTAssertEqual(dropped.count, 2)
        XCTAssertEqual(stack.deletions.count, ClipUndoStack.limit)
        XCTAssertFalse(stack.retainsImageFile(named: "shot-0.png"))
        XCTAssertTrue(stack.retainsImageFile(named: "shot-2.png"))
    }

    func testImageIsRetainedWhileADeletionIsUndoable() {
        var stack = ClipUndoStack()
        let item = ClipItem(type: .image, imageFileName: "shot.png")
        _ = stack.push([placement(item, index: 0)])
        XCTAssertTrue(stack.retainsImageFile(named: "shot.png"))
        XCTAssertNotNil(stack.pop())
        XCTAssertFalse(stack.retainsImageFile(named: "shot.png"))
    }

    func testRemoveAllHandsBackEverything() {
        var stack = ClipUndoStack()
        _ = stack.push([placement(ClipItem(type: .text, text: "x"), index: 0)])
        _ = stack.push([placement(ClipItem(type: .text, text: "y"), index: 0)])
        XCTAssertEqual(stack.removeAll().count, 2)
        XCTAssertTrue(stack.isEmpty)
    }

    func testRestorationIndexPrefersPredecessorThenSuccessorThenIndex() {
        let a = ClipItem(type: .text, text: "a")
        let b = ClipItem(type: .text, text: "b")
        let c = ClipItem(type: .text, text: "c")
        let gone = placement(b, index: 1, before: a, after: c)

        XCTAssertEqual(gone.restorationIndex(in: [a, c]), 1)
        XCTAssertEqual(gone.restorationIndex(in: [c, a]), 2)
        XCTAssertEqual(gone.restorationIndex(in: [c]), 0)
        XCTAssertEqual(gone.restorationIndex(in: []), 0)
        XCTAssertEqual(placement(b, index: 7).restorationIndex(in: [a, c]), 2)
    }
}
