import AppKit
import Observation

extension Notification.Name {
    static let saipasteStoreDidSave = Notification.Name("SaiPasteStoreDidSave")
}

/// Whether keyboard focus currently belongs to the native search field or
/// to the clip strip.
enum BarInputMode: Equatable {
    case cards
    case search
}

@Observable
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var history: [ClipItem] = []

    private var undoStack = ClipUndoStack()
    /// True while at least one deletion can be undone; drives the bar's Undo button.
    private(set) var hasUndoableDeletion = false

    var barInputMode: BarInputMode = .cards
    var searchText: String = "" {
        didSet { if searchText != oldValue { clearMultiSelection() } }
    }
    var selectedID: UUID?
    private(set) var multiSelectedIDs: Set<UUID> = []
    private var selectionAnchorID: UUID?

    /// Bumped every time the bar is about to present, so the strip can reset
    /// its scroll position even when the selection itself did not change.
    private(set) var barPresentationToken = 0

    var historyLimit: Int {
        get { Settings.shared.historyLimit }
        set { Settings.shared.historyLimit = newValue; trimHistory() }
    }

    private var storeURL: URL
    private var imagesDir: URL
    private var baseDir: URL
    private var saveWorkItem: DispatchWorkItem?

    static var localBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaiPaste", isDirectory: true)
    }

    /// The on-disk store root (history JSON plus saved images).
    var dataDirectory: URL { baseDir }

    private init() {
        let base = ClipboardStore.localBase
        baseDir = base
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        storeURL = base.appendingPathComponent("store.json")
        prepareDirectories()
        load()
        sweepOrphanImages()
    }

    private func prepareDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDir.path)
    }

    var visibleItems: [ClipItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return history }
        return history.filter { $0.searchableText.contains(q) }
    }

    var selectedItem: ClipItem? {
        guard let id = selectedID else { return nil }
        return visibleItems.first(where: { $0.id == id })
    }

    /// The selected clips in the order they appear on screen.
    var selectedItems: [ClipItem] {
        let ids = effectiveSelectionIDs
        return visibleItems.filter { ids.contains($0.id) }
    }

    func addCaptured(_ item: ClipItem) {
        if let idx = history.firstIndex(where: { $0.sameContent(as: item) }) {
            if item.imageFileName != history[idx].imageFileName { deleteImageFile(item) }
            var existing = history.remove(at: idx)
            existing.createdAt = item.createdAt
            history.insert(existing, at: 0)
            if searchText.isEmpty && multiSelectedIDs.isEmpty {
                selectedID = existing.id
                selectionAnchorID = existing.id
            }
            scheduleSave()
            return
        }
        history.insert(item, at: 0)
        trimHistory()
        if searchText.isEmpty && multiSelectedIDs.isEmpty {
            selectedID = item.id
            selectionAnchorID = item.id
        }
        scheduleSave()
    }

    /// A paste of an existing clip counts as using it: move it back to the
    /// front so the next paste starts where the user left off.
    func promoteCopiedItem(_ item: ClipItem, at date: Date = .now) {
        var copied = item
        copied.createdAt = date
        addCaptured(copied)
    }

    func applyRetentionPolicy() { trimHistory(); scheduleSave() }

    func retentionRemovalCount(mode: HistoryRetentionMode, limit: Int, days: Int) -> Int {
        switch mode {
        case .itemCount:
            return max(0, history.count - max(20, limit))
        case .timeInterval:
            // days == 0 means "forever" - no age-based cutoff, just the safety cap.
            guard let cutoff = Self.retentionCutoff(daysAgo: days) else {
                return max(0, history.count - Self.timeRetentionSafetyCap)
            }
            let byAge = history.filter { $0.createdAt < cutoff }.count
            return byAge + max(0, (history.count - byAge) - Self.timeRetentionSafetyCap)
        }
    }

    private static let timeRetentionSafetyCap = 5000

    private static func retentionCutoff(daysAgo days: Int) -> Date? {
        guard days > 0 else { return nil }
        return Date().addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    private func trimHistory() {
        var removed: [ClipItem] = []
        switch Settings.shared.historyRetentionMode {
        case .itemCount:
            if history.count > historyLimit {
                removed = Array(history[historyLimit...])
                history.removeLast(history.count - historyLimit)
            }
        case .timeInterval:
            if let cutoff = Self.retentionCutoff(daysAgo: Settings.shared.historyRetentionDays) {
                let old = history.filter { $0.createdAt < cutoff }
                if !old.isEmpty {
                    removed += old
                    history.removeAll { $0.createdAt < cutoff }
                }
            }
            if history.count > Self.timeRetentionSafetyCap {
                removed += Array(history[Self.timeRetentionSafetyCap...])
                history.removeLast(history.count - Self.timeRetentionSafetyCap)
            }
        }
        guard !removed.isEmpty else { return }
        for item in removed { deleteImageFile(item) }
        if let sel = selectedID, removed.contains(where: { $0.id == sel }) { selectFirst() }
        reconcileMultiSelection()
    }

    /// Deletes the selected clips. Every deletion stays undoable until the app
    /// quits (or 20 later deletions push it out).
    func delete(_ item: ClipItem) {
        delete(items: [item])
    }

    func delete(items: [ClipItem]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        // Captured before removal so repeated deletes walk down the list
        // instead of snapping back to the newest clip every time.
        let deletedIndex = visibleItems.firstIndex(where: { ids.contains($0.id) })
        let selectionDeleted = selectedID.map { ids.contains($0) } ?? false
        let placements = Self.placements(of: ids, in: history)
        history.removeAll { ids.contains($0.id) }

        for dropped in undoStack.push(placements) {
            for placement in dropped.placements { deleteImageFile(placement.item) }
        }
        hasUndoableDeletion = !undoStack.isEmpty

        multiSelectedIDs.subtract(ids)
        if multiSelectedIDs.count <= 1 { multiSelectedIDs = [] }
        if selectionDeleted {
            let remaining = visibleItems
            if let index = deletedIndex, !remaining.isEmpty {
                selectedID = remaining[min(index, remaining.count - 1)].id
            } else {
                selectFirst()
            }
            selectionAnchorID = selectedID
        }
        reconcileMultiSelection()
        scheduleSave()
    }

    private static func placements(of ids: Set<UUID>, in items: [ClipItem]) -> [ClipPlacement] {
        items.indices.compactMap { index in
            guard ids.contains(items[index].id) else { return nil }
            return ClipPlacement(index: index,
                                 item: items[index],
                                 predecessorID: index > 0 ? items[index - 1].id : nil,
                                 successorID: index + 1 < items.count ? items[index + 1].id : nil)
        }
    }

    /// Puts the newest deletion back where it was, every clip of a bulk delete
    /// at once.
    @discardableResult
    func undoLastDelete() -> Bool {
        guard let deletion = undoStack.pop() else { return false }
        var restored: [UUID] = []
        for placement in deletion.placements.sorted(by: { $0.index < $1.index }) {
            if restore(placement) { restored.append(placement.item.id) }
        }
        hasUndoableDeletion = !undoStack.isEmpty
        if let id = restored.first(where: { id in visibleItems.contains(where: { $0.id == id }) }) {
            selectedID = id
            selectionAnchorID = id
        }
        reconcileMultiSelection()
        scheduleSave()
        return true
    }

    /// A clip that came back by other means in the meantime (copied again) is
    /// left as it is rather than doubled.
    private func restore(_ placement: ClipPlacement) -> Bool {
        let item = placement.item
        if history.contains(where: { $0.id == item.id || $0.sameContent(as: item) }) {
            deleteImageFile(item)
            return false
        }
        history.insert(item, at: placement.restorationIndex(in: history))
        return true
    }

    /// Clear History forgets everything restorable, so nothing deleted earlier
    /// can come back into an empty list.
    func forgetDeletions() {
        for deletion in undoStack.removeAll() {
            for placement in deletion.placements { deleteImageFile(placement.item) }
        }
        hasUndoableDeletion = false
    }

    func clearHistory() {
        let old = history
        history.removeAll()
        selectedID = nil
        forgetDeletions()
        for item in old { deleteImageFile(item) }
        reconcileMultiSelection()
        scheduleSave()
    }

    func selectFirst() {
        selectedID = visibleItems.first?.id
        // An anchor left over from the previous presentation turns a Shift
        // click into a range measured from a card the user no longer sees.
        selectionAnchorID = selectedID
    }

    /// ⌘A: select every clip in the current (filtered) list. The cursor stays
    /// on the first card so the strip does not jump to the far end.
    func selectAllVisible() {
        let items = visibleItems
        guard let first = items.first else { return }
        selectedID = first.id
        selectionAnchorID = first.id
        multiSelectedIDs = items.count > 1 ? Set(items.map(\.id)) : []
    }

    var effectiveSelectionIDs: Set<UUID> {
        if !multiSelectedIDs.isEmpty { return multiSelectedIDs }
        return selectedID.map { [$0] } ?? []
    }

    func isSelected(_ id: UUID) -> Bool {
        if multiSelectedIDs.isEmpty { return selectedID == id }
        return multiSelectedIDs.contains(id)
    }

    func select(_ id: UUID) {
        selectedID = id
        selectionAnchorID = id
        multiSelectedIDs = []
    }

    func extendSelection(to id: UUID) {
        let items = visibleItems
        guard let targetIndex = items.firstIndex(where: { $0.id == id }) else { return }
        guard let anchor = selectionAnchorID ?? selectedID,
              let anchorIndex = items.firstIndex(where: { $0.id == anchor }) else {
            select(id)
            return
        }
        let range = items[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)]
        multiSelectedIDs = Set(range.map(\.id))
        selectedID = id
        selectionAnchorID = anchor
        if multiSelectedIDs.count <= 1 { multiSelectedIDs = [] }
    }

    func clearMultiSelection() {
        multiSelectedIDs = []
        selectionAnchorID = selectedID
    }

    private func reconcileMultiSelection() {
        guard !multiSelectedIDs.isEmpty else { return }
        let visible = Set(visibleItems.map(\.id))
        multiSelectedIDs.formIntersection(visible)
        if multiSelectedIDs.count <= 1 { multiSelectedIDs = [] }
        if let anchor = selectionAnchorID, !visible.contains(anchor) {
            selectionAnchorID = selectedID
        }
        if let sel = selectedID, !visible.contains(sel) {
            selectedID = multiSelectedIDs.first ?? visibleItems.first?.id
        }
    }

    func prepareForBarPresentation() {
        applyRetentionPolicy()
        clearMultiSelection()
        barPresentationToken &+= 1
        selectFirst()
    }

    func moveSelection(by delta: Int) {
        clearMultiSelection()
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else {
            selectedID = items.first?.id; return
        }
        let next = max(0, min(items.count - 1, idx + delta))
        selectedID = items[next].id
        selectionAnchorID = selectedID
    }

    func imageURL(for item: ClipItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func loadImage(for item: ClipItem) -> NSImage? {
        guard let url = imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    func storeImageData(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).png"
        let url = imagesDir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return name
        } catch { return nil }
    }

    private func deleteImageFile(_ item: ClipItem) {
        guard let name = item.imageFileName else { return }
        let stillUsed = history.contains { $0.imageFileName == name }
            || undoStack.retainsImageFile(named: name)
        if stillUsed { return }
        if let url = imageURL(for: item) { try? FileManager.default.removeItem(at: url) }
    }

    /// Deletes image files no clip points at, catching anything left behind by
    /// a crash while deletions were still undoable.
    private func sweepOrphanImages() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) else { return }
        let used = Set(history.compactMap(\.imageFileName))
        for file in files where file.pathExtension == "png" && !used.contains(file.lastPathComponent) {
            try? fm.removeItem(at: file)
        }
    }

    private struct Snapshot: Codable {
        var history: [ClipItem]
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        history = snap.history
        selectFirst()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        let snap = Snapshot(history: history)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: storeURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        NotificationCenter.default.post(name: .saipasteStoreDidSave, object: nil)
    }
}
