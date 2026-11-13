import AppKit

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let onTakeScreenshot: () -> Void
    private let onPinClipboardImage: () -> Void
    private let onRecord: () -> Void
    private let onColorPicker: () -> Void
    private let onOpenHistoryPanel: () -> Void
    private let onOpenSettings: () -> Void

    init(
        onTakeScreenshot: @escaping () -> Void,
        onPinClipboardImage: @escaping () -> Void,
        onRecord: @escaping () -> Void,
        onColorPicker: @escaping () -> Void,
        onOpenHistoryPanel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onTakeScreenshot = onTakeScreenshot
        self.onPinClipboardImage = onPinClipboardImage
        self.onRecord = onRecord
        self.onColorPicker = onColorPicker
        self.onOpenHistoryPanel = onOpenHistoryPanel
        self.onOpenSettings = onOpenSettings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        super.init()

        if let button = statusItem.button {
            button.image = Self.statusBarIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        setupMenu()

        NotificationCenter.default.addObserver(forName: .languageDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
        NotificationCenter.default.addObserver(forName: .historyCacheEnabledDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
        NotificationCenter.default.addObserver(forName: .clipboardTextCacheEnabledDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
        NotificationCenter.default.addObserver(forName: .hotkeyDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let screenshotItem = NSMenuItem(title: L10n.takeScreenshot, action: #selector(takeScreenshot), keyEquivalent: "")
        screenshotItem.target = self
        screenshotItem.image = Self.menuIcon(systemName: "crop")
        HotkeyManager.applyToMenuItem(screenshotItem)
        menu.addItem(screenshotItem)

        let pastePinItem = NSMenuItem(title: L10n.pastePin, action: #selector(pastePin), keyEquivalent: "")
        pastePinItem.target = self
        pastePinItem.image = Self.menuIcon(systemName: "pin")
        menu.addItem(pastePinItem)

        let recordItem = NSMenuItem(title: L10n.record, action: #selector(record), keyEquivalent: "")
        recordItem.target = self
        recordItem.image = Self.menuIcon(systemName: "record.circle")
        HotkeyManager.applyRecordToMenuItem(recordItem)
        menu.addItem(recordItem)

        let colorPickerItem = NSMenuItem(title: L10n.colorPicker, action: #selector(colorPicker), keyEquivalent: "")
        colorPickerItem.target = self
        colorPickerItem.image = Self.menuIcon(systemName: "eyedropper")
        HotkeyManager.applyColorPickerToMenuItem(colorPickerItem)
        menu.addItem(colorPickerItem)

        menu.addItem(NSMenuItem.separator())

        if Defaults.isHistoryCacheAvailable {
            let historyPanelItem = NSMenuItem(title: L10n.historyPanelMenu, action: #selector(openHistoryPanel), keyEquivalent: "")
            historyPanelItem.target = self
            historyPanelItem.image = Self.menuIcon(systemName: "rectangle.stack")
            HotkeyManager.applyHistoryPanelToMenuItem(historyPanelItem)
            menu.addItem(historyPanelItem)

            menu.addItem(NSMenuItem.separator())
        }

        let settingsItem = NSMenuItem(title: L10n.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = Self.menuIcon(systemName: "gearshape")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = Self.menuIcon(systemName: "power")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    fileprivate static func menuIcon(systemName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    private static func statusBarIcon() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = size
            image.isTemplate = true
            return image
        }

        let image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: AppIdentity.displayName
        )
            ?? NSImage(size: size)
        image.size = size
        image.isTemplate = true
        return image
    }

    @objc private func takeScreenshot() {
        onTakeScreenshot()
    }

    @objc private func pastePin() {
        onPinClipboardImage()
    }

    @objc private func record() {
        onRecord()
    }

    @objc private func colorPicker() {
        onColorPicker()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openHistoryPanel() {
        onOpenHistoryPanel()
    }

    func setMenuBarVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }
}
