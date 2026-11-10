import AppKit
import ImageIO

/// Light history browser: past screenshots grouped by day, plus a small action
/// bar (copy / edit / pin / reveal in Finder / delete). Replaces the old
/// animated timeline panel.
final class HistoryPanelController {
    private let onEditEntry: (HistoryEntry) -> Void
    private var panel: HistoryPanelWindow?
    private var contentStack: NSStackView?
    private var scrollView: NSScrollView?
    private var copyButton: NSButton?
    private var editButton: NSButton?
    private var pinButton: NSButton?
    private var revealButton: NSButton?
    private var deleteButton: NSButton?
    private var selectedEntry: HistoryEntry?
    private var thumbnails: [HistoryThumbnailButton] = []
    private var observers: [NSObjectProtocol] = []

    private static let thumbnailSize = NSSize(width: 148, height: 96)
    private static let panelSize = NSSize(width: 780, height: 560)

    init(onEditEntry: @escaping (HistoryEntry) -> Void) {
        self.onEditEntry = onEditEntry
        observers.append(NotificationCenter.default.addObserver(
            forName: .historyDidUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reloadIfVisible()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        panel?.close()
    }

    // MARK: - Presentation

    func toggleFromUserRequest(holdOpenUntilMouseEnters: Bool = false) {
        guard Defaults.historyCacheEnabled else { return }
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func close() {
        panel?.close()
    }

    private func show() {
        let window = panel ?? makePanel()
        panel = window
        reload()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> HistoryPanelWindow {
        let window = HistoryPanelWindow(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.historyMenu
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.onCancel = { [weak self] in self?.close() }

        let root = NSView()
        window.contentView = root

        let scroll = NSScrollView()
        scrollView = scroll
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        // `.width` makes every arranged subview (headers and thumbnail grids)
        // stretch to the panel width, so the grid always knows how many
        // thumbnails fit per row.
        stack.alignment = .width
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // A flipped document view is what keeps the content anchored at the
        // top: NSScrollView positions an unflipped document's origin at the
        // bottom-left, which pushed every row to the bottom of the panel and
        // left a large empty area above it.
        let document = HistoryDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        contentStack = stack

        let bar = makeActionBar()

        root.addSubview(scroll)
        root.addSubview(bar)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),

            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 30),

            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        updateActionState()
        return window
    }

    private func makeActionBar() -> NSStackView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false

        let copy = makeBarButton(title: L10n.tipConfirm, action: #selector(copySelected))
        let edit = makeBarButton(title: L10n.imageMergeContinueEditing, action: #selector(editSelected))
        let pin = makeBarButton(title: L10n.tipPin, action: #selector(pinSelected))
        let reveal = makeBarButton(title: L10n.historyShowInFinder, action: #selector(revealSelected))
        let delete = makeBarButton(title: L10n.historyDelete, action: #selector(deleteSelected))
        copyButton = copy
        editButton = edit
        pinButton = pin
        revealButton = reveal
        deleteButton = delete

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(spacer)
        for button in [copy, edit, pin, reveal, delete] {
            bar.addArrangedSubview(button)
        }
        return bar
    }

    private func makeBarButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 12)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    // MARK: - Content

    private func reloadIfVisible() {
        guard panel?.isVisible == true else { return }
        reload()
    }

    private func reload() {
        guard let stack = contentStack else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        thumbnails.removeAll()
        selectedEntry = nil

        let entries = HistoryManager.shared.imageEntries()
        guard !entries.isEmpty else {
            let empty = NSTextField(labelWithString: L10n.historyEmpty)
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
            updateActionState()
            return
        }

        for section in Self.groupedByDay(entries) {
            let header = NSTextField(labelWithString: section.title)
            header.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            header.textColor = .secondaryLabelColor
            stack.addArrangedSubview(header)

            let buttons = section.entries.map { entry -> HistoryThumbnailButton in
                let button = HistoryThumbnailButton(entry: entry, size: Self.thumbnailSize)
                button.target = self
                button.action = #selector(thumbnailClicked(_:))
                thumbnails.append(button)
                return button
            }
            let grid = HistoryThumbnailGrid()
            grid.setButtons(buttons)
            stack.addArrangedSubview(grid)
        }
        updateActionState()
        scrollToTop()
    }

    /// A flipped document view starts at y = 0, so this pins the panel to the
    /// newest screenshots instead of whatever offset the previous session left.
    private func scrollToTop() {
        guard let scrollView else { return }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private struct DaySection {
        let title: String
        let entries: [HistoryEntry]
    }

    private static func groupedByDay(_ entries: [HistoryEntry]) -> [DaySection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var order: [Date] = []
        var buckets: [Date: [HistoryEntry]] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if buckets[day] == nil {
                buckets[day] = []
                order.append(day)
            }
            buckets[day]?.append(entry)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"

        return order.map { day in
            let title: String
            if day == today {
                title = L10n.historyToday
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday {
                title = L10n.historyYesterday
            } else {
                title = formatter.string(from: day)
            }
            return DaySection(title: title, entries: buckets[day] ?? [])
        }
    }

    // MARK: - Selection

    private func select(_ entry: HistoryEntry, button: HistoryThumbnailButton) {
        selectedEntry = entry
        for thumbnail in thumbnails {
            thumbnail.isSelectedThumbnail = (thumbnail === button)
        }
        updateActionState()
    }

    private func updateActionState() {
        let hasSelection = selectedEntry != nil
        for button in [copyButton, editButton, pinButton, revealButton, deleteButton] {
            button?.isEnabled = hasSelection
        }
    }

    // MARK: - Actions

    @objc private func thumbnailClicked(_ sender: HistoryThumbnailButton) {
        guard let entry = sender.entry else { return }
        select(entry, button: sender)
        if NSApp.currentEvent?.clickCount == 2 {
            editSelected()
        }
    }

    @objc private func copySelected() {
        guard let entry = selectedEntry,
              let image = HistoryManager.shared.image(for: entry) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @objc private func editSelected() {
        guard let entry = selectedEntry else { return }
        close()
        onEditEntry(entry)
    }

    @objc private func pinSelected() {
        guard let entry = selectedEntry,
              let image = HistoryManager.shared.image(for: entry) else { return }
        PinLauncher.pin(image: image, source: nil, saveToHistory: false)
        close()
    }

    @objc private func revealSelected() {
        guard let entry = selectedEntry else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.fileURL])
    }

    @objc private func deleteSelected() {
        guard let entry = selectedEntry else { return }
        HistoryManager.shared.remove([entry]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
    }
}

/// Top-anchored document view. `NSScrollView` treats a plain `NSView` document
/// as bottom-origin, which parked everything at the bottom of the panel.
private final class HistoryDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Lays thumbnails out in rows that wrap at the current width, so overflow
/// scrolls vertically instead of disappearing off the right edge.
private final class HistoryThumbnailGrid: NSView {
    private static let itemSize = NSSize(width: 148, height: 96)
    private static let spacing: CGFloat = 10

    private var buttons: [HistoryThumbnailButton] = []
    private var heightConstraint: NSLayoutConstraint?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = heightAnchor.constraint(equalToConstant: 0)
        constraint.priority = NSLayoutConstraint.Priority(999)
        constraint.isActive = true
        heightConstraint = constraint
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setButtons(_ newButtons: [HistoryThumbnailButton]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = newButtons
        for button in newButtons {
            addSubview(button)
        }
        needsLayout = true
        updateHeight()
    }

    override func layout() {
        super.layout()
        updateHeight()

        let columns = Self.columnCount(for: bounds.width)
        for (index, button) in buttons.enumerated() {
            let row = index / columns
            let column = index % columns
            button.frame = NSRect(
                x: CGFloat(column) * (Self.itemSize.width + Self.spacing),
                y: CGFloat(row) * (Self.itemSize.height + Self.spacing),
                width: Self.itemSize.width,
                height: Self.itemSize.height
            )
        }
    }

    private static func columnCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let count = Int((width + spacing) / (itemSize.width + spacing))
        return max(1, count)
    }

    private func updateHeight() {
        guard let heightConstraint else { return }
        let columns = Self.columnCount(for: bounds.width)
        let rows = max(1, Int(ceil(Double(buttons.count) / Double(columns))))
        let height = CGFloat(rows) * Self.itemSize.height + CGFloat(rows - 1) * Self.spacing
        if abs(heightConstraint.constant - height) > 0.5 {
            heightConstraint.constant = height
        }
    }
}

/// Panel that turns Esc into a close request.
private final class HistoryPanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Thumbnail button that draws its own selection ring.
private final class HistoryThumbnailButton: NSButton {
    let entry: HistoryEntry?
    private let thumb: NSImage?

    var isSelectedThumbnail: Bool = false {
        didSet { needsDisplay = true }
    }

    init(entry: HistoryEntry, size: NSSize) {
        self.entry = entry
        self.thumb = Self.thumbnail(for: entry, maxPixel: max(size.width, size.height) * 2)
        super.init(frame: NSRect(origin: .zero, size: size))
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        toolTip = entry.createdAt.formatted(date: .abbreviated, time: .shortened)
        setAccessibilityLabel(entry.fileURL.lastPathComponent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 148, height: 96)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        if let thumb {
            let target = Self.fitted(thumb.size, in: bounds.insetBy(dx: 4, dy: 4))
            thumb.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        let stroke: NSColor = isSelectedThumbnail ? .controlAccentColor : NSColor.separatorColor
        stroke.setStroke()
        path.lineWidth = isSelectedThumbnail ? 2.5 : 1
        path.stroke()
    }

    private static func fitted(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Decoding a full screenshot for a 148×96 thumbnail is expensive when the
     /// panel relayouts on resize, so decoded thumbnails are cached per file.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    private static func thumbnail(for entry: HistoryEntry, maxPixel: CGFloat) -> NSImage? {
        let key = "\(entry.fileURL.path)|\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = makeThumbnail(for: entry.fileURL, maxPixel: maxPixel) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func makeThumbnail(for url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }
}
