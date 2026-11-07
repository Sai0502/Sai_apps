import Foundation

/// Where a deleted clip sat, so Undo puts it back where it was instead of at
/// the front of the list.
struct ClipPlacement {
    let index: Int
    let item: ClipItem
    let predecessorID: UUID?
    let successorID: UUID?

    func restorationIndex(in items: [ClipItem]) -> Int {
        if let predecessorID, let i = items.firstIndex(where: { $0.id == predecessorID }) { return i + 1 }
        if let successorID, let i = items.firstIndex(where: { $0.id == successorID }) { return i }
        return min(max(0, index), items.count)
    }
}

/// One delete operation, restorable as a whole: a bulk delete comes back
/// with a single Undo.
struct ClipDeletion {
    let placements: [ClipPlacement]
}

/// Deletions that can still be undone. Memory only, valid until the app quits,
/// and capped so deleted clips and their images cannot pile up forever.
struct ClipUndoStack {
    static let limit = 20

    private(set) var deletions: [ClipDeletion] = []

    var isEmpty: Bool { deletions.isEmpty }

    /// Returns the deletions dropped by the cap so their image files can be
    /// released.
    mutating func push(_ placements: [ClipPlacement]) -> [ClipDeletion] {
        guard !placements.isEmpty else { return [] }
        deletions.append(ClipDeletion(placements: placements))
        var dropped: [ClipDeletion] = []
        while deletions.count > Self.limit {
            dropped.append(deletions.removeFirst())
        }
        return dropped
    }

    mutating func pop() -> ClipDeletion? {
        deletions.popLast()
    }

    mutating func removeAll() -> [ClipDeletion] {
        defer { deletions.removeAll() }
        return deletions
    }

    func retainsImageFile(named name: String) -> Bool {
        deletions.contains { $0.placements.contains { $0.item.imageFileName == name } }
    }
}
