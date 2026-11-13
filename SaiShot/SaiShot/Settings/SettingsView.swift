import AppKit
import Carbon
import PermissionFlow

// MARK: - Tab model

enum SettingsTab: CaseIterable {
    case general
    case shortcuts
    case toolbar
    case recording
    case translation
    case permissions

    var title: String {
        switch self {
        case .general: return L10n.settingsTabGeneral
        case .shortcuts: return L10n.settingsTabShortcuts
        case .recording: return L10n.settingsGeneralRecording
        case .toolbar: return L10n.settingsTabToolbar
        case .translation: return L10n.settingsTabTranslation
        case .permissions: return L10n.settingsTabPermissions
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "keyboard"
        case .recording: return "record.circle"
        case .toolbar: return "slider.horizontal.3"
        case .translation: return "translate"
        case .permissions: return "lock.shield.fill"
        }
    }

    var iconTint: NSColor {
        switch self {
        case .general: return NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.72, alpha: 1.0)
        case .shortcuts:
            return NSColor(calibratedRed: 0.36, green: 0.66, blue: 0.98, alpha: 1.0)
        case .toolbar, .recording:
            return NSColor(calibratedRed: 0.95, green: 0.54, blue: 0.62, alpha: 1.0)
        case .translation:
            return NSColor(calibratedRed: 0.38, green: 0.80, blue: 0.78, alpha: 1.0)
        case .permissions: return NSColor(calibratedRed: 0.36, green: 0.78, blue: 0.50, alpha: 1.0)
        }
    }
}

class SettingsView: NSView {

    var onMenuBarToggle: ((Bool) -> Void)?

    // Switches
    private var menuBarSwitch: NSSwitch!
    private var launchAtLoginSwitch: NSSwitch!

    // Picker & slider
    private var langPicker: NSPopUpButton!

    private var historyCacheSlider: SettingsTickSlider!
    private var historyCacheValueLabel: NSTextField!

    // Window-capture shadow card

    // Screenshot shortcut card
    private var shortcutTitleLabel: NSTextField!
    private var shortcutField: NSTextField!
    private var shortcutSetButton: NSButton!
    private var shortcutRestoreButton: NSButton!
    private var shortcutRecordingMonitor: Any?

    // Full-screen screenshot shortcut card

    // Color picker shortcut card
    private var colorPickerShortcutTitleLabel: NSTextField!
    private var colorPickerShortcutField: NSTextField!
    private var colorPickerShortcutSetButton: NSButton!
    private var colorPickerShortcutRestoreButton: NSButton!
    private var colorPickerShortcutRecordingMonitor: Any?

    // Quick Pin shortcut card

    // Pin selected image shortcut card

    // Pin clipboard image shortcut card

    // Pin clipboard text shortcut card

    // Edit selected image shortcut card

    // Edit clipboard image shortcut card

    // Text recognition shortcut card

    // Copy image text shortcut card
    private var copyImageTextShortcutTitleLabel: NSTextField!
    private var copyImageTextShortcutField: NSTextField!
    private var copyImageTextShortcutSetButton: NSButton!
    private var copyImageTextShortcutRestoreButton: NSButton!
    private var copyImageTextShortcutRecordingMonitor: Any?

    // Screenshot translation shortcut card
    private var screenshotTranslationShortcutTitleLabel: NSTextField!
    private var screenshotTranslationShortcutField: NSTextField!
    private var screenshotTranslationShortcutSetButton: NSButton!
    private var screenshotTranslationShortcutRestoreButton: NSButton!
    private var screenshotTranslationShortcutRecordingMonitor: Any?

    // Recording shortcut card

    // Image Merge shortcut card

    // File upload shortcut card

    // Copy-to-clipboard (editor confirm) shortcut card

    // Save-to-file shortcut card (default ⌘S)

    // History navigation shortcut cards



    private var shortcutResetButton: NSButton?

    // Permission badges
    private var accessibilityBadge: StatusBadge!
    private var screenRecordingBadge: StatusBadge!
    private var microphoneBadge: StatusBadge?

    // Sidebar bottom action — Launch App in startup mode, Quit App otherwise.

    // Labels (kept for language switching)
    private var menuBarTitleLabel: NSTextField!
    private var launchAtLoginTitleLabel: NSTextField!
    private var langTitleLabel: NSTextField!
    private var historyCacheTitleLabel: NSTextField!
    private var permHeaderSubtitleLabel: NSTextField?
    private var accessibilityNameLabel: NSTextField!
    private var accessibilityDescLabel: NSTextField!
    private var screenRecordingNameLabel: NSTextField!
    private var screenRecordingDescLabel: NSTextField!
    private var microphoneNameLabel: NSTextField?
    private var microphoneDescLabel: NSTextField?

    // Sidebar / detail chrome
    private var selectedTab: SettingsTab = .general
    private var tabButtons: [TabButton] = []
    private var detailTitleLabel: NSTextField!
    private var detailScrollView: NSScrollView!

    private var paneContainer: NSView!
    private var paneViews: [SettingsTab: NSView] = [:]
    private var toolbarPane: ToolbarSettingsPane?
    private var filenameRuleCard: FilenameRuleCard?
    private var savePathTitleLabel: NSTextField!
    private var savePathSubtitleLabel: NSTextField!
    private var recordingSavePathTitleLabel: NSTextField!
    private var recordingSavePathValueLabel: NSTextField!
    private var recordingSavePathChooseButton: NSButton!
    private var recordingSavePathRevealButton: NSButton!
    private var recordingSaveFormatTitleLabel: NSTextField!
    private var recordingSaveFormatPopup: NSPopUpButton!
    private var recordingSystemAudioTitleLabel: NSTextField?
    private var recordingSystemAudioHintLabel: NSTextField?
    private var recordingSystemAudioSwitch: NSSwitch?
    private var recordingMicrophoneTitleLabel: NSTextField?
    private var recordingMicrophoneHintLabel: NSTextField?
    private var recordingMicrophoneSwitch: NSSwitch?
    private var recordingMicrophoneDeviceTitleLabel: NSTextField?
    private var recordingMicrophoneDevicePopup: NSPopUpButton?
    private var screenshotSavePathTitleLabel: NSTextField!
    private var screenshotSavePathValueLabel: NSTextField!
    private var screenshotSavePathChooseButton: NSButton!
    private var screenshotSavePathRevealButton: NSButton!

    private var refreshTimer: Timer?
    private var gradientLayer: CAGradientLayer?
    private lazy var permissionFlowController = PermissionFlow.makeController(
        configuration: PermissionFlowConfiguration(
            requiredAppURLs: [Bundle.main.bundleURL],
            localeIdentifier: Defaults.language.lprojName
        )
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        setupBackground()
        setupUI()
        startRefreshTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateLocalization),
            name: .languageDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTimer?.invalidate()
        cancelShortcutRecording()
        cancelColorPickerShortcutRecording()
        cancelCopyImageTextShortcutRecording()
        cancelScreenshotTranslationShortcutRecording()
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = bounds
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Background

    private func setupBackground() {
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.17, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.10, alpha: 1.0).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)
        gradientLayer = gradient
    }

    // MARK: - Layout

    private func setupUI() {
        let sidebar = buildSidebar()
        addSubview(sidebar)

        let detail = buildDetailPanel()
        addSubview(detail)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            sidebar.widthAnchor.constraint(equalToConstant: 224),

            detail.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            detail.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 12),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])

        // Build all panes
        buildCapturePreferencePanes()
        paneViews[.shortcuts] = buildShortcutsPane()
        paneViews[.toolbar] = buildToolbarPane()
        paneViews[.translation] = buildTranslationPane()
        paneViews[.permissions] = buildPermissionsPane()

        // Default selection
        selectTab(.general)

        refreshPermissionStatus()
        refreshShortcutDisplay()
        refreshColorPickerShortcutDisplay()
        refreshCopyImageTextShortcutDisplay()
        refreshScreenshotTranslationShortcutDisplay()
    }

    // MARK: - Sidebar

    private func buildSidebar() -> NSView {
        let panel = SidebarPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let navigation = NSScrollView()
        navigation.translatesAutoresizingMaskIntoConstraints = false
        navigation.drawsBackground = false
        navigation.hasVerticalScroller = false
        navigation.verticalScroller = nil
        navigation.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sidebarBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: navigation.contentView
        )
        panel.addSubview(navigation)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        navigation.documentView = document
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: navigation.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: navigation.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: navigation.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        for tab in SettingsTab.allCases {
            let btn = TabButton(tab: tab)
            btn.target = self
            btn.action = #selector(tabClicked(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            tabButtons.append(btn)
            stack.addArrangedSubview(btn)
            btn.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            navigation.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            navigation.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            navigation.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            navigation.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
        ])

        return panel
    }

    @objc private func sidebarBoundsDidChange() {
        for button in tabButtons {
            button.refreshHoverAtCurrentMouseLocation()
        }
    }

    private func appVersionString() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(short)"
    }

    private func makeBuildConfigurationBadge() -> NSView {
        #if DEBUG
        let title = "DEBUG"
        let color = NSColor.systemOrange
        #else
        let title = "RELEASE"
        let color = NSColor.systemGreen
        #endif

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.cornerCurve = .continuous
        badge.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
        ])
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        return badge
    }

    @objc private func tabClicked(_ sender: TabButton) {
        selectTab(sender.tab)
    }

    private func selectTab(_ tab: SettingsTab) {
        if selectedTab == .toolbar && tab != .toolbar {
            toolbarPane?.cancelShortcutRecording()
        }
        window?.makeFirstResponder(nil)
        selectedTab = tab
        for btn in tabButtons {
            btn.isSelected = (btn.tab == tab)
        }
        detailTitleLabel?.stringValue = tab.title

        // Rebuild the mic device list on every visit so hot-plugs appear.
        if tab == .recording {
            refreshMicrophoneDevicePopup()
        }

        // Swap pane content
        guard let pane = paneViews[tab] else { return }
        for sub in paneContainer.subviews { sub.removeFromSuperview() }
        pane.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: paneContainer.topAnchor),
            pane.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
        ])
        layoutSubtreeIfNeeded()
        detailScrollView.contentView.scroll(to: .zero)
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }

    // MARK: - Detail panel

    private func buildDetailPanel() -> NSView {
        let panel = DetailPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false

        // Title
        let title = NSTextField(labelWithString: SettingsTab.general.title)
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        title.textColor = NSColor.white.withAlphaComponent(0.96)
        title.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(title)
        detailTitleLabel = title

        // Scroll view fills the rest of the panel — the launch / quit action
        // lives in the sidebar bottom now, freeing the right-pane footer.
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
        panel.addSubview(scroll)
        detailScrollView = scroll

        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = container
        paneContainer = container

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 22),
            title.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -22),

            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor),

            container.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        return panel
    }

    // MARK: - Pane builders

    private func buildCapturePreferencePanes() {
        let basic = paneStack()
        let recording = paneStack()

        let togglesCard = CardView()
        let togglesInner = verticalInnerStack()
        togglesCard.addSubview(togglesInner)
        pin(togglesInner, to: togglesCard, insets: NSEdgeInsets(top: 14, left: 14, bottom: 6, right: 14))
        let langRow = NSStackView()
        langRow.orientation = .horizontal
        langRow.alignment = .centerY
        langRow.spacing = 10
        langRow.translatesAutoresizingMaskIntoConstraints = false

        langTitleLabel = primaryLabel(L10n.languageHeader)
        langRow.addArrangedSubview(langTitleLabel)
        langRow.addArrangedSubview(flexSpacer())

        langPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        langPicker.addItems(withTitles: AppLanguage.allCases.map { $0.displayName })
        langPicker.selectItem(at: AppLanguage.allCases.firstIndex(of: Defaults.language) ?? 0)
        langPicker.target = self
        langPicker.action = #selector(languageChanged(_:))
        langPicker.controlSize = .small
        langPicker.font = NSFont.systemFont(ofSize: 12)
        langRow.addArrangedSubview(langPicker)

        togglesInner.addArrangedSubview(langRow)
        langRow.widthAnchor.constraint(equalTo: togglesInner.widthAnchor).isActive = true
        togglesInner.setCustomSpacing(14, after: langRow)
        togglesInner.addArrangedSubview(rowDivider())
        let menuBar = makeToggleRow(
            title: L10n.showMenuBarIcon,
            subtitle: nil,
            isOn: Defaults.showMenuBar,
            action: #selector(menuBarSwitchToggled(_:))
        )
        menuBarTitleLabel = menuBar.title
        menuBarSwitch = menuBar.toggle
        togglesInner.addArrangedSubview(menuBar.row)
        menuBar.row.widthAnchor.constraint(equalTo: togglesInner.widthAnchor).isActive = true
        togglesInner.addArrangedSubview(rowDivider())

        let login = makeToggleRow(
            title: L10n.launchAtLogin,
            subtitle: nil,
            isOn: LaunchAtLogin.isEnabled,
            action: #selector(launchAtLoginToggled(_:))
        )
        launchAtLoginTitleLabel = login.title
        launchAtLoginSwitch = login.toggle
        togglesInner.addArrangedSubview(login.row)
        login.row.widthAnchor.constraint(equalTo: togglesInner.widthAnchor).isActive = true

        basic.addArrangedSubview(togglesCard)
        togglesCard.widthAnchor.constraint(equalTo: basic.widthAnchor).isActive = true

        buildRecordingCard(into: recording)
        buildSavePathCard(into: basic)
        let filenameCard = FilenameRuleCard()
        filenameRuleCard = filenameCard
        basic.addArrangedSubview(filenameCard)
        filenameCard.widthAnchor.constraint(equalTo: basic.widthAnchor).isActive = true

        buildHistoryLimitCard(into: basic)

        let ocrCard = CardView()
        let ocrPane = OCRSettingsPane()
        ocrCard.addSubview(ocrPane)
        pin(ocrPane, to: ocrCard, insets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
        basic.addArrangedSubview(ocrCard)
        ocrCard.widthAnchor.constraint(equalTo: basic.widthAnchor).isActive = true

        paneViews[.general] = wrapPane(basic)
        paneViews[.recording] = wrapPane(recording)
    }

    /// Window-capture shadow card: a toggle for the rounded-corner + drop
    /// shadow effect, a size slider, and a live preview of the result.
    private func refreshSavePathControls() {
        recordingSavePathValueLabel?.stringValue = SaveDestination.displayPath(Defaults.recordingSaveDirectory)
        screenshotSavePathValueLabel?.stringValue = SaveDestination.displayPath(Defaults.screenshotSaveDirectory)
        recordingSavePathValueLabel?.toolTip = Defaults.recordingSaveDirectory.path
        screenshotSavePathValueLabel?.toolTip = Defaults.screenshotSaveDirectory.path
        refreshRecordingSaveFormatPopup()
    }

    private func refreshRecordingSaveFormatPopup() {
        guard let popup = recordingSaveFormatPopup else { return }
        let selected = Defaults.recordingSavePreference
        popup.removeAllItems()
        for preference in RecordingSavePreference.allCases {
            popup.addItem(withTitle: preference.displayName)
            popup.lastItem?.representedObject = preference.rawValue
        }
        if let index = RecordingSavePreference.allCases.firstIndex(of: selected) {
            popup.selectItem(at: index)
        }
    }

    /// Rebuild the mic device popup from the live CoreAudio list; falls back
    /// to "System Default" when the persisted UID is unplugged.
    private func refreshMicrophoneDevicePopup() {
        guard let popup = recordingMicrophoneDevicePopup else { return }
        let selectedUID = Defaults.recordingMicrophoneDeviceUID
        popup.removeAllItems()
        popup.addItem(withTitle: L10n.recordingMicrophoneDeviceDefault)
        popup.lastItem?.representedObject = nil
        for device in AudioInputDevices.available() {
            popup.addItem(withTitle: device.name)
            popup.lastItem?.representedObject = device.uid
        }
        if let selectedUID,
           let index = (0..<popup.numberOfItems).first(where: {
               popup.item(at: $0)?.representedObject as? String == selectedUID
           }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func updateMicrophoneControlsEnabled() {
        let enabled = Defaults.recordingMicrophoneEnabled
        recordingMicrophoneDevicePopup?.isEnabled = enabled
        recordingMicrophoneDeviceTitleLabel?.textColor = NSColor.white.withAlphaComponent(enabled ? 0.94 : 0.4)
    }

    @objc private func recordingMicrophoneDeviceChanged(_ sender: NSPopUpButton) {
        Defaults.recordingMicrophoneDeviceUID = sender.selectedItem?.representedObject as? String
    }

    private func buildShortcutsPane() -> NSView {
        let stack = paneStack()

        // Screenshot shortcut card
        let shortcut = buildShortcutCard(
            title: L10n.shortcutHeader,
            setAction: #selector(shortcutSetClicked),
            restoreAction: #selector(shortcutRestoreClicked),
            clearKey: "screenshot"
        )
        shortcutTitleLabel = shortcut.title
        shortcutField = shortcut.field
        shortcutSetButton = shortcut.setButton
        shortcutRestoreButton = shortcut.restoreButton
        stack.addArrangedSubview(shortcut.card)
        shortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Full-screen screenshot shortcut card
        // Color picker shortcut card
        let colorPickerShortcut = buildShortcutCard(
            title: L10n.colorPickerShortcutHeader,
            setAction: #selector(colorPickerShortcutSetClicked),
            restoreAction: #selector(colorPickerShortcutRestoreClicked),
            clearKey: "colorPicker"
        )
        colorPickerShortcutTitleLabel = colorPickerShortcut.title
        colorPickerShortcutField = colorPickerShortcut.field
        colorPickerShortcutSetButton = colorPickerShortcut.setButton
        colorPickerShortcutRestoreButton = colorPickerShortcut.restoreButton
        stack.addArrangedSubview(colorPickerShortcut.card)
        colorPickerShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Copy image text shortcut card
        let copyImageTextShortcut = buildShortcutCard(
            title: L10n.copyImageTextShortcutHeader,
            setAction: #selector(copyImageTextShortcutSetClicked),
            restoreAction: #selector(copyImageTextShortcutRestoreClicked),
            clearKey: "copyImageText"
        )
        copyImageTextShortcutTitleLabel = copyImageTextShortcut.title
        copyImageTextShortcutField = copyImageTextShortcut.field
        copyImageTextShortcutSetButton = copyImageTextShortcut.setButton
        copyImageTextShortcutRestoreButton = copyImageTextShortcut.restoreButton
        stack.addArrangedSubview(copyImageTextShortcut.card)
        copyImageTextShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Screenshot translation shortcut card
        let screenshotTranslationShortcut = buildShortcutCard(
            title: L10n.screenshotTranslationShortcutHeader,
            setAction: #selector(screenshotTranslationShortcutSetClicked),
            restoreAction: #selector(screenshotTranslationShortcutRestoreClicked),
            clearKey: "screenshotTranslation"
        )
        screenshotTranslationShortcutTitleLabel = screenshotTranslationShortcut.title
        screenshotTranslationShortcutField = screenshotTranslationShortcut.field
        screenshotTranslationShortcutSetButton = screenshotTranslationShortcut.setButton
        screenshotTranslationShortcutRestoreButton = screenshotTranslationShortcut.restoreButton
        stack.addArrangedSubview(screenshotTranslationShortcut.card)
        screenshotTranslationShortcut.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: L10n.toolbarSettingsReset,
                                   target: self,
                                   action: #selector(shortcutsResetClicked))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .large
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
        shortcutResetButton = resetButton

        footer.addArrangedSubview(flexSpacer())
        footer.addArrangedSubview(resetButton)
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return wrapPane(stack)
    }

    /// History retention limit card. Caching itself is always on, so only the
    /// number of kept images/videos is exposed.
    private func buildHistoryLimitCard(into stack: NSStackView) {
        let historyCard = CardView()
        let historyInner = NSStackView()
        historyInner.orientation = .vertical
        historyInner.alignment = .leading
        historyInner.spacing = 10
        historyInner.translatesAutoresizingMaskIntoConstraints = false
        historyCard.addSubview(historyInner)
        pin(historyInner, to: historyCard, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        let historyHeader = NSStackView()
        historyHeader.orientation = .horizontal
        historyHeader.alignment = .firstBaseline
        historyHeader.spacing = 8
        historyHeader.translatesAutoresizingMaskIntoConstraints = false

        historyCacheTitleLabel = primaryLabel(L10n.historyCacheLabel)
        historyHeader.addArrangedSubview(historyCacheTitleLabel)
        historyHeader.addArrangedSubview(flexSpacer())

        historyCacheValueLabel = NSTextField(labelWithString: "\(Defaults.historyCacheLimit)")
        historyCacheValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        historyCacheValueLabel.textColor = NSColor.white.withAlphaComponent(0.88)
        historyHeader.addArrangedSubview(historyCacheValueLabel)

        historyInner.addArrangedSubview(historyHeader)
        historyHeader.widthAnchor.constraint(equalTo: historyInner.widthAnchor).isActive = true

        let slider = SettingsTickSlider(
            value: Double(Defaults.historyCacheLimit),
            minValue: Double(Defaults.historyCacheMin),
            maxValue: Double(Defaults.historyCacheMax),
            stepValue: Double(Defaults.historyCacheStep),
            numberOfTickMarks: (Defaults.historyCacheMax - Defaults.historyCacheMin) / Defaults.historyCacheStep + 1,
            target: self,
            action: #selector(historyCacheSliderChanged(_:))
        )
        slider.translatesAutoresizingMaskIntoConstraints = false
        historyCacheSlider = slider
        historyInner.addArrangedSubview(slider)
        slider.widthAnchor.constraint(equalTo: historyInner.widthAnchor).isActive = true

        stack.addArrangedSubview(historyCard)
        historyCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func buildSavePathCard(into stack: NSStackView) {
        let card = CardView()
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
        header.translatesAutoresizingMaskIntoConstraints = false

        savePathTitleLabel = primaryLabel(L10n.savePathTitle)
        savePathSubtitleLabel = secondaryLabel(L10n.savePathSubtitle, wrapping: true)
        header.addArrangedSubview(savePathTitleLabel)
        savePathTitleLabel.toolTip = L10n.savePathSubtitle
        inner.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let topDivider = rowDivider()
        inner.addArrangedSubview(topDivider)
        topDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let screenshotPath = makeSavePathRow(
            title: L10n.screenshotSavePathLabel,
            chooseAction: #selector(chooseScreenshotSavePathClicked),
            revealAction: #selector(revealScreenshotSavePathClicked)
        )
        screenshotSavePathTitleLabel = screenshotPath.title
        screenshotSavePathValueLabel = screenshotPath.value
        screenshotSavePathChooseButton = screenshotPath.chooseButton
        screenshotSavePathRevealButton = screenshotPath.revealButton
        inner.addArrangedSubview(screenshotPath.row)
        screenshotPath.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let pathDivider = rowDivider()
        inner.addArrangedSubview(pathDivider)
        pathDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let recordingPath = makeSavePathRow(
            title: L10n.recordingSavePathLabel,
            chooseAction: #selector(chooseRecordingSavePathClicked),
            revealAction: #selector(revealRecordingSavePathClicked)
        )
        recordingSavePathTitleLabel = recordingPath.title
        recordingSavePathValueLabel = recordingPath.value
        recordingSavePathChooseButton = recordingPath.chooseButton
        recordingSavePathRevealButton = recordingPath.revealButton
        inner.addArrangedSubview(recordingPath.row)
        recordingPath.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        refreshSavePathControls()
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func buildRecordingCard(into stack: NSStackView) {
        let card = CardView()
        let inner = paneStack()
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        let formatRow = NSStackView()
        formatRow.orientation = .horizontal
        formatRow.alignment = .centerY
        formatRow.spacing = 10
        formatRow.translatesAutoresizingMaskIntoConstraints = false

        recordingSaveFormatTitleLabel = primaryLabel(L10n.recordingSaveFormatSettingLabel)
        formatRow.addArrangedSubview(recordingSaveFormatTitleLabel)
        formatRow.addArrangedSubview(flexSpacer())

        recordingSaveFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        recordingSaveFormatPopup.controlSize = .small
        recordingSaveFormatPopup.font = NSFont.systemFont(ofSize: 12)
        recordingSaveFormatPopup.target = self
        recordingSaveFormatPopup.action = #selector(recordingSaveFormatPreferenceChanged(_:))
        recordingSaveFormatPopup.translatesAutoresizingMaskIntoConstraints = false
        recordingSaveFormatPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        formatRow.addArrangedSubview(recordingSaveFormatPopup)
        inner.addArrangedSubview(formatRow)
        formatRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let audioDivider = rowDivider()
        inner.addArrangedSubview(audioDivider)
        audioDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let systemAudioToggle = makeToggleRow(
            title: L10n.recordingSystemAudioLabel,
            subtitle: L10n.recordingSystemAudioHint,
            isOn: Defaults.recordingSystemAudioEnabled,
            action: #selector(recordingSystemAudioToggled(_:))
        )
        recordingSystemAudioTitleLabel = systemAudioToggle.title
        recordingSystemAudioHintLabel = systemAudioToggle.subtitle
        recordingSystemAudioSwitch = systemAudioToggle.toggle
        inner.addArrangedSubview(systemAudioToggle.row)
        systemAudioToggle.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let micDivider = rowDivider()
        inner.addArrangedSubview(micDivider)
        micDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let micToggle = makeToggleRow(
            title: L10n.recordingMicrophoneLabel,
            subtitle: L10n.recordingMicrophoneHint,
            isOn: Defaults.recordingMicrophoneEnabled,
            action: #selector(recordingMicrophoneToggled(_:))
        )
        recordingMicrophoneTitleLabel = micToggle.title
        recordingMicrophoneHintLabel = micToggle.subtitle
        recordingMicrophoneSwitch = micToggle.toggle
        inner.addArrangedSubview(micToggle.row)
        micToggle.row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let micDeviceDivider = rowDivider()
        inner.addArrangedSubview(micDeviceDivider)
        micDeviceDivider.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let micDeviceRow = NSStackView()
        micDeviceRow.orientation = .horizontal
        micDeviceRow.alignment = .centerY
        micDeviceRow.spacing = 10
        micDeviceRow.translatesAutoresizingMaskIntoConstraints = false

        recordingMicrophoneDeviceTitleLabel = primaryLabel(L10n.recordingMicrophoneDeviceLabel)
        micDeviceRow.addArrangedSubview(recordingMicrophoneDeviceTitleLabel!)
        micDeviceRow.addArrangedSubview(flexSpacer())

        recordingMicrophoneDevicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        recordingMicrophoneDevicePopup?.controlSize = .small
        recordingMicrophoneDevicePopup?.font = NSFont.systemFont(ofSize: 12)
        recordingMicrophoneDevicePopup?.target = self
        recordingMicrophoneDevicePopup?.action = #selector(recordingMicrophoneDeviceChanged(_:))
        recordingMicrophoneDevicePopup?.translatesAutoresizingMaskIntoConstraints = false
        recordingMicrophoneDevicePopup?.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        micDeviceRow.addArrangedSubview(recordingMicrophoneDevicePopup!)
        inner.addArrangedSubview(micDeviceRow)
        micDeviceRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        refreshMicrophoneDevicePopup()

        refreshRecordingSaveFormatPopup()
        updateMicrophoneControlsEnabled()
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeSavePathRow(
        title: String,
        chooseAction: Selector,
        revealAction: Selector
    ) -> (row: NSView, title: NSTextField, value: NSTextField, chooseButton: NSButton, revealButton: NSButton) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let valueLabel = secondaryLabel("", wrapping: false)
        valueLabel.isSelectable = true
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let chooseButton = NSButton(title: L10n.savePathChoose, target: self, action: chooseAction)
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        chooseButton.font = NSFont.systemFont(ofSize: 11)
        chooseButton.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(chooseButton)

        let revealButton = NSButton(title: L10n.savePathReveal, target: self, action: revealAction)
        revealButton.bezelStyle = .rounded
        revealButton.controlSize = .small
        revealButton.font = NSFont.systemFont(ofSize: 11)
        revealButton.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(revealButton)

        return (row, titleLabel, valueLabel, chooseButton, revealButton)
    }

    private func buildToolbarPane() -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        let pane = ToolbarSettingsPane()
        toolbarPane = pane
        host.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: host.topAnchor),
            pane.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        return host
    }

    func cancelToolbarShortcutRecording() {
        toolbarPane?.cancelShortcutRecording()
    }

    private func buildTranslationPane() -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        let pane = TranslationSettingsPane()
        host.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: host.topAnchor),
            pane.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        return host
    }

    private func buildPermissionsPane() -> NSView {
        let stack = paneStack()

        let permCard = CardView()
        let permInner = verticalInnerStack()
        permCard.addSubview(permInner)
        pin(permInner, to: permCard, insets: NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))

        let acc = makePermissionRow(
            name: L10n.accessibilityPermission,
            description: L10n.accessibilityDescription,
            action: #selector(openAccessibilitySettings(_:))
        )
        accessibilityNameLabel = acc.name
        accessibilityDescLabel = acc.desc
        accessibilityBadge = acc.badge
        permInner.addArrangedSubview(acc.row)
        acc.row.widthAnchor.constraint(equalTo: permInner.widthAnchor).isActive = true
        permInner.addArrangedSubview(rowDivider())

        let sc = makePermissionRow(
            name: L10n.screenRecordingPermission,
            description: L10n.screenRecordingDescription,
            action: #selector(openScreenRecordingSettings(_:))
        )
        screenRecordingNameLabel = sc.name
        screenRecordingDescLabel = sc.desc
        screenRecordingBadge = sc.badge
        permInner.addArrangedSubview(sc.row)
        sc.row.widthAnchor.constraint(equalTo: permInner.widthAnchor).isActive = true

        let micDivider = rowDivider()
        permInner.addArrangedSubview(micDivider)
        micDivider.widthAnchor.constraint(equalTo: permInner.widthAnchor).isActive = true

        // Microphone is optional: the Launch button is not gated on it, but
        // the row lets users grant it from Settings directly.
        let mic = makePermissionRow(
            name: L10n.microphonePermission,
            description: L10n.microphoneDescription,
            action: #selector(openMicrophoneSettings(_:))
        )
        microphoneNameLabel = mic.name
        microphoneDescLabel = mic.desc
        microphoneBadge = mic.badge
        permInner.addArrangedSubview(mic.row)
        mic.row.widthAnchor.constraint(equalTo: permInner.widthAnchor).isActive = true

        stack.addArrangedSubview(permCard)
        permCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return wrapPane(stack)
    }

    /// "Updates" row — a status label plus a button whose role tracks state:
    private func paneStack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 12
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    private func wrapPane(_ stack: NSStackView) -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -22),
        ])
        return host
    }

    // MARK: - Builders

    private func verticalInnerStack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    private func rowDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func flexSpacer() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return v
    }

    private func primaryLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        l.textColor = NSColor.white.withAlphaComponent(0.94)
        return l
    }

    private func secondaryLabel(_ text: String, wrapping: Bool = false) -> NSTextField {
        let l = wrapping ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = NSColor.white.withAlphaComponent(0.58)
        if wrapping {
            l.preferredMaxLayoutWidth = 360
        }
        return l
    }

    private func pin(_ child: NSView, to parent: NSView, insets: NSEdgeInsets) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
        ])
    }

    private struct ShortcutCardBuild {
        let card: CardView
        let title: NSTextField
        let field: NSTextField
        let setButton: NSButton
        let restoreButton: NSButton
        let clearButton: NSButton
    }

    private func buildShortcutCard(
        title: String,
        setAction: Selector,
        restoreAction: Selector,
        clearKey: String
    ) -> ShortcutCardBuild {
        let card = CardView()
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(flexSpacer())

        let field = NSTextField()
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .center
        field.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        field.textColor = NSColor.white.withAlphaComponent(0.92)
        field.translatesAutoresizingMaskIntoConstraints = false

        let fieldBackground = NSView()
        fieldBackground.wantsLayer = true
        fieldBackground.layer?.cornerRadius = 5
        fieldBackground.layer?.cornerCurve = .continuous
        fieldBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        fieldBackground.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        fieldBackground.layer?.borderWidth = 1
        fieldBackground.translatesAutoresizingMaskIntoConstraints = false
        fieldBackground.addSubview(field)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: fieldBackground.topAnchor, constant: 4),
            field.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor, constant: -4),
            field.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: -10),
            fieldBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])
        row.addArrangedSubview(fieldBackground)

        let setButton = NSButton(title: L10n.shortcutSet, target: self, action: setAction)
        setButton.bezelStyle = .rounded
        setButton.controlSize = .small
        setButton.font = NSFont.systemFont(ofSize: 12)
        setButton.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(setButton)

        let restoreButton = NSButton(
            image: NSImage(
                systemSymbolName: "arrow.counterclockwise.circle.fill",
                accessibilityDescription: L10n.shortcutRestore
            ) ?? NSImage(),
            target: self,
            action: restoreAction
        )
        restoreButton.bezelStyle = .inline
        restoreButton.isBordered = false
        restoreButton.imagePosition = .imageOnly
        restoreButton.contentTintColor = NSColor.white.withAlphaComponent(0.62)
        restoreButton.toolTip = L10n.shortcutRestore
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(restoreButton)

        let clearButton = NSButton(
            image: NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: L10n.shortcutClear
            ) ?? NSImage(),
            target: self,
            action: #selector(shortcutClearClicked(_:))
        )
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = NSColor.white.withAlphaComponent(0.62)
        clearButton.toolTip = L10n.shortcutClear
        clearButton.identifier = NSUserInterfaceItemIdentifier(clearKey)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(clearButton)

        inner.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        return ShortcutCardBuild(
            card: card,
            title: titleLabel,
            field: field,
            setButton: setButton,
            restoreButton: restoreButton,
            clearButton: clearButton
        )
    }

    private struct ToggleRowBuild {
        let row: NSView
        let title: NSTextField
        let subtitle: NSTextField?
        let toggle: NSSwitch
    }

    private func makeToggleRow(
        title: String,
        subtitle: String?,
        isOn: Bool,
        action: Selector
    ) -> ToggleRowBuild {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleLabel)

        var subtitleLabel: NSTextField? = nil
        if let subtitle {
            let sub = secondaryLabel(subtitle, wrapping: true)
            textStack.addArrangedSubview(sub)
            subtitleLabel = sub
        }

        let sw = NSSwitch()
        sw.state = isOn ? .on : .off
        sw.target = self
        sw.action = action
        sw.controlSize = .small
        sw.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(textStack)
        row.addSubview(sw)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: sw.leadingAnchor, constant: -12),

            sw.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            sw.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
        ])

        return ToggleRowBuild(row: row, title: titleLabel, subtitle: subtitleLabel, toggle: sw)
    }

    private struct RadioRowBuild {
        let row: NSView
        let title: NSTextField
        let subtitle: NSTextField?
        let button: NSButton
    }

    private func makeRadioRow(
        title: String,
        subtitle: String?,
        isOn: Bool,
        action: Selector
    ) -> RadioRowBuild {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleLabel)

        var subtitleLabel: NSTextField? = nil
        if let subtitle {
            let sub = secondaryLabel(subtitle, wrapping: true)
            textStack.addArrangedSubview(sub)
            subtitleLabel = sub
        }

        let button = NSButton(radioButtonWithTitle: "", target: self, action: action)
        button.state = isOn ? .on : .off
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(textStack)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
        ])

        return RadioRowBuild(row: row, title: titleLabel, subtitle: subtitleLabel, button: button)
    }

    private struct PermissionRowBuild {
        let row: NSView
        let name: NSTextField
        let desc: NSTextField
        let badge: StatusBadge
    }

    private func makePermissionRow(
        name: String,
        description: String,
        action: Selector
    ) -> PermissionRowBuild {
        let button = HoverButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action
        button.title = ""
        button.isBordered = false
        button.cornerRadius = 10

        let nameLbl = primaryLabel(name)
        nameLbl.translatesAutoresizingMaskIntoConstraints = false

        let badge = StatusBadge()
        badge.translatesAutoresizingMaskIntoConstraints = false

        let topLine = NSStackView(views: [nameLbl, badge])
        topLine.orientation = .horizontal
        topLine.alignment = .centerY
        topLine.spacing = 8
        topLine.translatesAutoresizingMaskIntoConstraints = false

        let descLbl = secondaryLabel(description, wrapping: true)
        descLbl.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(topLine)
        textStack.addArrangedSubview(descLbl)

        let chevron = NSTextField(labelWithString: "\u{203A}")
        chevron.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        chevron.textColor = NSColor.white.withAlphaComponent(0.32)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        button.addSubview(textStack)
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: button.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -12),
            textStack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -10),

            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
        ])

        return PermissionRowBuild(row: button, name: nameLbl, desc: descLbl, badge: badge)
    }

    func showPermissionsTab() {
        selectTab(.permissions)
    }

    // MARK: - Permission polling

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }

    func refreshPermissionStatus() {
        let accessibilityGranted = AppPermissions.accessibilityGranted
        let screenRecordingGranted = AppPermissions.screenRecordingGranted

        accessibilityBadge?.configure(granted: accessibilityGranted)
        screenRecordingBadge?.configure(granted: screenRecordingGranted)
        microphoneBadge?.configure(granted: AppPermissions.microphoneGranted)

    }

    // MARK: - Actions

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let cases = AppLanguage.allCases
        let index = sender.indexOfSelectedItem
        guard cases.indices.contains(index) else { return }
        Defaults.language = cases[index]
    }

    @objc private func recordingSaveFormatPreferenceChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let preference = RecordingSavePreference(rawValue: raw)
        else {
            return
        }
        Defaults.recordingSavePreference = preference
    }

    @objc private func chooseRecordingSavePathClicked() {
        chooseSaveDirectory(
            title: L10n.chooseRecordingSavePathTitle,
            currentURL: Defaults.recordingSaveDirectory
        ) { url in
            Defaults.recordingSaveDirectory = url
            self.refreshSavePathControls()
        }
    }

    @objc private func chooseScreenshotSavePathClicked() {
        chooseSaveDirectory(
            title: L10n.chooseScreenshotSavePathTitle,
            currentURL: Defaults.screenshotSaveDirectory
        ) { url in
            Defaults.screenshotSaveDirectory = url
            self.refreshSavePathControls()
        }
    }

    @objc private func revealRecordingSavePathClicked() {
        revealSaveDirectory(Defaults.recordingSaveDirectory)
    }

    @objc private func revealScreenshotSavePathClicked() {
        revealSaveDirectory(Defaults.screenshotSaveDirectory)
    }

    private func chooseSaveDirectory(
        title: String,
        currentURL: URL,
        completion: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = L10n.savePathChoose
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURLForPanel(currentURL)

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            panel.begin(completionHandler: handle)
        }
    }

    private func directoryURLForPanel(_ url: URL) -> URL {
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let parent = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            return parent
        }
        return Defaults.defaultScreenshotSaveDirectory.deletingLastPathComponent()
    }

    private func revealSaveDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func historyCacheSliderChanged(_ sender: SettingsTickSlider) {
        guard Defaults.historyCacheEnabled else {
            sender.doubleValue = Double(Defaults.historyCacheLimit)
            return
        }
        let value = Int(sender.doubleValue.rounded())
        Defaults.historyCacheLimit = value
        let normalizedValue = Defaults.historyCacheLimit
        sender.doubleValue = Double(normalizedValue)
        historyCacheValueLabel?.stringValue = "\(normalizedValue)"
    }

    @objc private func screenParametersChanged() {
    }

    @objc private func recordingSystemAudioToggled(_ sender: NSSwitch) {
        Defaults.recordingSystemAudioEnabled = sender.state == .on
    }

    @objc private func recordingMicrophoneToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        Defaults.recordingMicrophoneEnabled = enabled
        updateMicrophoneControlsEnabled()
        guard enabled else { return }

        // Once denied, macOS won't re-prompt — bounce to System Settings and
        // revert the toggle so the UI stays truthful.
        if AppPermissions.microphoneGranted {
            return
        }
        if AppPermissions.microphoneDenied {
            sender.state = .off
            Defaults.recordingMicrophoneEnabled = false
            updateMicrophoneControlsEnabled()
            presentMicrophoneDeniedAlert()
            return
        }
        AppPermissions.requestMicrophonePermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.refreshPermissionStatus()
                return
            }
            // User declined the prompt or an error occurred. Revert.
            self.recordingMicrophoneSwitch?.state = .off
            Defaults.recordingMicrophoneEnabled = false
            self.updateMicrophoneControlsEnabled()
            self.refreshPermissionStatus()
        }
    }

    private func presentMicrophoneDeniedAlert() {
        guard let win = self.window else { return }
        let alert = NSAlert()
        alert.messageText = L10n.recordingMicrophoneDeniedTitle
        alert.informativeText = L10n.recordingMicrophoneDeniedMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.recordingMicrophoneOpenSettings)
        alert.addButton(withTitle: L10n.shortcutCancel)
        alert.beginSheetModal(for: win) { response in
            if response == .alertFirstButtonReturn {
                self.openMicrophoneSystemSettings()
            }
        }
    }

    @objc private func launchAtLoginToggled(_ sender: NSSwitch) {
        let enable = sender.state == .on
        let ok = LaunchAtLogin.setEnabled(enable)
        if !ok {
            sender.state = LaunchAtLogin.isEnabled ? .on : .off
        }
    }

    @objc private func menuBarSwitchToggled(_ sender: NSSwitch) {
        let visible = sender.state == .on
        Defaults.showMenuBar = visible
        onMenuBarToggle?(visible)
    }

    @objc private func openAccessibilitySettings(_ sender: NSButton) {
        startPermissionFlow(.accessibility, from: sender)
    }

    @objc private func openScreenRecordingSettings(_ sender: NSButton) {
        startPermissionFlow(.screenRecording, from: sender)
    }

    @objc private func openMicrophoneSettings(_ sender: NSButton) {
        // Microphone is optional and macOS will not re-prompt once a decision
        // has been made. If a decision is still pending, request inline; if it
        // was already denied, jump straight to System Settings.
        if AppPermissions.microphoneGranted {
            return
        }
        if AppPermissions.microphoneDenied {
            openMicrophoneSystemSettings()
            return
        }
        AppPermissions.requestMicrophonePermission { [weak self] granted in
            guard let self else { return }
            self.refreshPermissionStatus()
            if !granted {
                self.openMicrophoneSystemSettings()
            }
        }
    }

    private func openMicrophoneSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func startPermissionFlow(_ pane: PermissionFlowPane, from sourceView: NSView) {
        permissionFlowController.setLocaleIdentifier(Defaults.language.lprojName)
        updateMicrophoneControlsEnabled()
        permissionFlowController.authorize(
            pane: pane,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: sourceFrameInScreen(for: sourceView)
        )
    }

    private func sourceFrameInScreen(for view: NSView) -> CGRect? {
        guard let window = view.window else { return nil }
        let frameInWindow = view.convert(view.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    func closePermissionFlowPanel() {
        permissionFlowController.closePanel()
    }

    // MARK: - Shortcut recording

    /// Tells the user a recorded combo is already taken by another function,
    /// so they can pick a different one. Recording is already cancelled by the
    /// caller before this is shown.
    private func presentHotkeyConflictAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.shortcutConflictTitle
        alert.informativeText = message
        alert.alertStyle = .warning
        if let win = self.window {
            alert.beginSheetModal(for: win, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// Tells the user a recorded key needs a modifier held with it, so they
    /// can try again. Recording is already cancelled by the caller before
    /// this is shown.
    private func presentShortcutNeedsModifierAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.shortcutNeedsModifierTitle
        alert.informativeText = L10n.shortcutNeedsModifier
        alert.alertStyle = .warning
        if let win = self.window {
            alert.beginSheetModal(for: win, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func cancelShortcutRecordings(except slot: HotkeyManager.HotkeySlot) {
        if slot != .screenshot, shortcutRecordingMonitor != nil {
            cancelShortcutRecording()
        }
        if slot != .colorPicker, colorPickerShortcutRecordingMonitor != nil {
            cancelColorPickerShortcutRecording()
        }
        if slot != .copyImageText, copyImageTextShortcutRecordingMonitor != nil {
            cancelCopyImageTextShortcutRecording()
        }
        if slot != .screenshotTranslation, screenshotTranslationShortcutRecordingMonitor != nil {
            cancelScreenshotTranslationShortcutRecording()
        }
    }

    @objc private func shortcutSetClicked() {
        if shortcutRecordingMonitor != nil {
            cancelShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .screenshot)
        HotkeyManager.shared.beginRecording()
        shortcutSetButton.title = L10n.shortcutCancel
        shortcutField.stringValue = L10n.shortcutWaiting
        shortcutRestoreButton.isHidden = true

        shortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            // Reject bare keys (no modifier and not a function key) — the user must
            // hold at least one modifier so the shortcut won't collide with typing.
            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .screenshot) {
                self.cancelShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.screenshotHotkeyKeyCode = Int(keyCode)
            Defaults.screenshotHotkeyModifiers = Int(carbonMods)
            self.finishShortcutRecording()
            return nil
        }
    }

    @objc private func shortcutRestoreClicked() {
        if shortcutRecordingMonitor != nil {
            cancelShortcutRecording()
        }
        Defaults.clearScreenshotHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshShortcutDisplay()
    }

    private func finishShortcutRecording() {
        if let m = shortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            shortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshShortcutDisplay()
    }

    func cancelShortcutRecording() {
        guard shortcutRecordingMonitor != nil else { return }
        if let m = shortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            shortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshShortcutDisplay()
    }

    private func refreshShortcutDisplay() {
        shortcutSetButton?.title = L10n.shortcutSet
        if Defaults.screenshotHotkeyDisabled {
            shortcutField?.stringValue = L10n.shortcutUnset
            shortcutRestoreButton?.isHidden = false
        } else if let display = HotkeyManager.currentDisplayString() {
            shortcutField?.stringValue = display
            shortcutRestoreButton?.isHidden = false
        } else {
            shortcutField?.stringValue = L10n.shortcutDefaultDisplay
            shortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func colorPickerShortcutSetClicked() {
        if colorPickerShortcutRecordingMonitor != nil {
            cancelColorPickerShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .colorPicker)
        HotkeyManager.shared.beginRecording()
        colorPickerShortcutSetButton.title = L10n.shortcutCancel
        colorPickerShortcutField.stringValue = L10n.shortcutWaiting
        colorPickerShortcutRestoreButton.isHidden = true

        colorPickerShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelColorPickerShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelColorPickerShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .colorPicker) {
                self.cancelColorPickerShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.colorPickerHotkeyKeyCode = Int(keyCode)
            Defaults.colorPickerHotkeyModifiers = Int(carbonMods)
            self.finishColorPickerShortcutRecording()
            return nil
        }
    }

    @objc private func colorPickerShortcutRestoreClicked() {
        if colorPickerShortcutRecordingMonitor != nil {
            cancelColorPickerShortcutRecording()
        }
        Defaults.clearColorPickerHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshColorPickerShortcutDisplay()
    }

    private func finishColorPickerShortcutRecording() {
        if let m = colorPickerShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            colorPickerShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshColorPickerShortcutDisplay()
    }

    func cancelColorPickerShortcutRecording() {
        guard colorPickerShortcutRecordingMonitor != nil else { return }
        if let m = colorPickerShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            colorPickerShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshColorPickerShortcutDisplay()
    }

    private func refreshColorPickerShortcutDisplay() {
        colorPickerShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentColorPickerDisplayString() {
            colorPickerShortcutField?.stringValue = display
            colorPickerShortcutRestoreButton?.isHidden = false
        } else {
            colorPickerShortcutField?.stringValue = L10n.colorPickerShortcutDefaultDisplay
            colorPickerShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func copyImageTextShortcutSetClicked() {
        if copyImageTextShortcutRecordingMonitor != nil {
            cancelCopyImageTextShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .copyImageText)
        HotkeyManager.shared.beginRecording()
        copyImageTextShortcutSetButton.title = L10n.shortcutCancel
        copyImageTextShortcutField.stringValue = L10n.shortcutWaiting
        copyImageTextShortcutRestoreButton.isHidden = true

        copyImageTextShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelCopyImageTextShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelCopyImageTextShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .copyImageText) {
                self.cancelCopyImageTextShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.copyImageTextHotkeyKeyCode = Int(keyCode)
            Defaults.copyImageTextHotkeyModifiers = Int(carbonMods)
            self.finishCopyImageTextShortcutRecording()
            return nil
        }
    }

    @objc private func copyImageTextShortcutRestoreClicked() {
        if copyImageTextShortcutRecordingMonitor != nil {
            cancelCopyImageTextShortcutRecording()
        }
        Defaults.clearCopyImageTextHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshCopyImageTextShortcutDisplay()
    }

    private func finishCopyImageTextShortcutRecording() {
        if let m = copyImageTextShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            copyImageTextShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshCopyImageTextShortcutDisplay()
    }

    func cancelCopyImageTextShortcutRecording() {
        guard copyImageTextShortcutRecordingMonitor != nil else { return }
        if let m = copyImageTextShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            copyImageTextShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshCopyImageTextShortcutDisplay()
    }

    private func refreshCopyImageTextShortcutDisplay() {
        copyImageTextShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentCopyImageTextDisplayString() {
            copyImageTextShortcutField?.stringValue = display
            copyImageTextShortcutRestoreButton?.isHidden = false
        } else {
            copyImageTextShortcutField?.stringValue = L10n.copyImageTextShortcutDefaultDisplay
            copyImageTextShortcutRestoreButton?.isHidden = true
        }
    }

    @objc private func screenshotTranslationShortcutSetClicked() {
        if screenshotTranslationShortcutRecordingMonitor != nil {
            cancelScreenshotTranslationShortcutRecording()
            return
        }
        cancelShortcutRecordings(except: .screenshotTranslation)
        HotkeyManager.shared.beginRecording()
        screenshotTranslationShortcutSetButton.title = L10n.shortcutCancel
        screenshotTranslationShortcutField.stringValue = L10n.shortcutWaiting
        screenshotTranslationShortcutRestoreButton.isHidden = true

        screenshotTranslationShortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let activeModifierMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedModifiers = modifiers.intersection(activeModifierMask)

            if isEscape && pressedModifiers.isEmpty {
                self.cancelScreenshotTranslationShortcutRecording()
                return nil
            }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)

            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.cancelScreenshotTranslationShortcutRecording()
                self.presentShortcutNeedsModifierAlert()
                return nil
            }

            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode, modifiers: carbonMods, assigningTo: .screenshotTranslation) {
                self.cancelScreenshotTranslationShortcutRecording()
                self.presentHotkeyConflictAlert(conflict)
                return nil
            }

            Defaults.screenshotTranslationHotkeyKeyCode = Int(keyCode)
            Defaults.screenshotTranslationHotkeyModifiers = Int(carbonMods)
            self.finishScreenshotTranslationShortcutRecording()
            return nil
        }
    }

    @objc private func screenshotTranslationShortcutRestoreClicked() {
        if screenshotTranslationShortcutRecordingMonitor != nil {
            cancelScreenshotTranslationShortcutRecording()
        }
        Defaults.clearScreenshotTranslationHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshScreenshotTranslationShortcutDisplay()
    }

    private func finishScreenshotTranslationShortcutRecording() {
        if let m = screenshotTranslationShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            screenshotTranslationShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshScreenshotTranslationShortcutDisplay()
    }

    func cancelScreenshotTranslationShortcutRecording() {
        guard screenshotTranslationShortcutRecordingMonitor != nil else { return }
        if let m = screenshotTranslationShortcutRecordingMonitor {
            NSEvent.removeMonitor(m)
            screenshotTranslationShortcutRecordingMonitor = nil
        }
        HotkeyManager.shared.endRecording()
        refreshScreenshotTranslationShortcutDisplay()
    }

    private func refreshScreenshotTranslationShortcutDisplay() {
        screenshotTranslationShortcutSetButton?.title = L10n.shortcutSet
        if let display = HotkeyManager.currentScreenshotTranslationDisplayString() {
            screenshotTranslationShortcutField?.stringValue = display
            screenshotTranslationShortcutRestoreButton?.isHidden = false
        } else {
            screenshotTranslationShortcutField?.stringValue = L10n.screenshotTranslationShortcutDefaultDisplay
            screenshotTranslationShortcutRestoreButton?.isHidden = true
        }
    }

    /// Small × on each shortcut row: drops the binding entirely so the row
    /// reads "未设置" and the action has no keystroke until recorded again.
    @objc private func shortcutClearClicked(_ sender: NSButton) {
        switch sender.identifier?.rawValue {
        case "screenshot":
            Defaults.disableScreenshotHotkey()
            refreshShortcutDisplay()
        case "colorPicker":
            Defaults.clearColorPickerHotkey()
            refreshColorPickerShortcutDisplay()
        case "copyImageText":
            Defaults.clearCopyImageTextHotkey()
            refreshCopyImageTextShortcutDisplay()
        case "screenshotTranslation":
            Defaults.clearScreenshotTranslationHotkey()
            refreshScreenshotTranslationShortcutDisplay()
        default:
            return
        }
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    @objc private func shortcutsResetClicked() {
        cancelShortcutRecording()
        cancelColorPickerShortcutRecording()
        cancelCopyImageTextShortcutRecording()
        cancelScreenshotTranslationShortcutRecording()

        Defaults.resetShortcutHotkeysToDefaults()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshShortcutDisplay()
        refreshColorPickerShortcutDisplay()
        refreshCopyImageTextShortcutDisplay()
        refreshScreenshotTranslationShortcutDisplay()
    }

    @objc private func updateLocalization() {
        permissionFlowController.setLocaleIdentifier(Defaults.language.lprojName)
        updateMicrophoneControlsEnabled()
        menuBarTitleLabel?.stringValue = L10n.showMenuBarIcon
        launchAtLoginTitleLabel?.stringValue = L10n.launchAtLogin
        langTitleLabel?.stringValue = L10n.languageHeader
        filenameRuleCard?.refreshLocalization()
        savePathTitleLabel?.stringValue = L10n.savePathTitle
        savePathSubtitleLabel?.stringValue = L10n.savePathSubtitle
        savePathTitleLabel?.toolTip = L10n.savePathSubtitle
        recordingSavePathTitleLabel?.stringValue = L10n.recordingSavePathLabel
        recordingSaveFormatTitleLabel?.stringValue = L10n.recordingSaveFormatSettingLabel
        recordingSystemAudioTitleLabel?.stringValue = L10n.recordingSystemAudioLabel
        recordingSystemAudioHintLabel?.stringValue = L10n.recordingSystemAudioHint
        recordingMicrophoneTitleLabel?.stringValue = L10n.recordingMicrophoneLabel
        recordingMicrophoneHintLabel?.stringValue = L10n.recordingMicrophoneHint
        recordingSystemAudioSwitch?.state = Defaults.recordingSystemAudioEnabled ? .on : .off
        recordingMicrophoneSwitch?.state = Defaults.recordingMicrophoneEnabled ? .on : .off
        recordingMicrophoneDeviceTitleLabel?.stringValue = L10n.recordingMicrophoneDeviceLabel
        refreshMicrophoneDevicePopup()
        screenshotSavePathTitleLabel?.stringValue = L10n.screenshotSavePathLabel
        recordingSavePathChooseButton?.title = L10n.savePathChoose
        recordingSavePathRevealButton?.title = L10n.savePathReveal
        screenshotSavePathChooseButton?.title = L10n.savePathChoose
        screenshotSavePathRevealButton?.title = L10n.savePathReveal
        refreshSavePathControls()
        accessibilityNameLabel?.stringValue = L10n.accessibilityPermission
        accessibilityDescLabel?.stringValue = L10n.accessibilityDescription
        screenRecordingNameLabel?.stringValue = L10n.screenRecordingPermission
        screenRecordingDescLabel?.stringValue = L10n.screenRecordingDescription
        microphoneNameLabel?.stringValue = L10n.microphonePermission
        microphoneDescLabel?.stringValue = L10n.microphoneDescription
        historyCacheTitleLabel?.stringValue = L10n.historyCacheLabel
        shortcutTitleLabel?.stringValue = L10n.shortcutHeader
        shortcutRestoreButton?.toolTip = L10n.shortcutRestore
        colorPickerShortcutTitleLabel?.stringValue = L10n.colorPickerShortcutHeader
        colorPickerShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        copyImageTextShortcutTitleLabel?.stringValue = L10n.copyImageTextShortcutHeader
        copyImageTextShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        screenshotTranslationShortcutTitleLabel?.stringValue = L10n.screenshotTranslationShortcutHeader
        screenshotTranslationShortcutRestoreButton?.toolTip = L10n.shortcutRestore
        shortcutResetButton?.title = L10n.toolbarSettingsReset
        refreshShortcutDisplay()
        refreshColorPickerShortcutDisplay()
        refreshCopyImageTextShortcutDisplay()
        refreshScreenshotTranslationShortcutDisplay()
        accessibilityBadge?.refreshTitle()
        screenRecordingBadge?.refreshTitle()
        microphoneBadge?.refreshTitle()
        for btn in tabButtons { btn.refreshTitle() }
        detailTitleLabel?.stringValue = selectedTab.title
        window?.title = L10n.settingsTitle
    }
}

// MARK: - Flipped view (top-aligned scroll content)

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Sidebar / detail panels

private final class SidebarPanel: NSView {
    private var gradientLayer: CAGradientLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 1

        let g = CAGradientLayer()
        g.colors = [
            NSColor(calibratedRed: 0.11, green: 0.17, blue: 0.25, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.18, alpha: 1.0).cgColor,
        ]
        g.startPoint = CGPoint(x: 0, y: 1)
        g.endPoint = CGPoint(x: 1, y: 0)
        g.cornerRadius = 22
        layer?.insertSublayer(g, at: 0)
        gradientLayer = g
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = bounds
    }
}

private final class DetailPanel: NSView {
    private var gradientLayer: CAGradientLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.cornerCurve = .continuous
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1

        let g = CAGradientLayer()
        g.colors = [
            NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0).cgColor,
        ]
        g.startPoint = CGPoint(x: 0, y: 1)
        g.endPoint = CGPoint(x: 1, y: 0)
        g.cornerRadius = 24
        layer?.insertSublayer(g, at: 0)
        gradientLayer = g
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = bounds
    }
}

/// A hairline that fades to transparent at both edges of the sidebar.
private final class SidebarSeparatorView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        gradient.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradient)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        let thickness = 1 / scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = CGRect(x: 0, y: (bounds.midY * scale).rounded() / scale,
                                width: bounds.width, height: thickness)
        CATransaction.commit()
    }
}

// MARK: - Sidebar tab button

private final class TabButton: NSControl {
    let tab: SettingsTab
    private let iconChip = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var isSelected: Bool = false {
        didSet { applyAppearance() }
    }

    init(tab: SettingsTab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        iconChip.translatesAutoresizingMaskIntoConstraints = false
        iconChip.wantsLayer = true
        iconChip.layer?.cornerRadius = 8
        iconChip.layer?.cornerCurve = .continuous
        iconChip.layer?.borderWidth = 1
        addSubview(iconChip)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown
        iconChip.addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.stringValue = tab.title
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),

            iconChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconChip.widthAnchor.constraint(equalToConstant: 28),
            iconChip.heightAnchor.constraint(equalToConstant: 28),

            iconView.centerXAnchor.constraint(equalTo: iconChip.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconChip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconChip.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tab.title)
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshTitle() {
        label.stringValue = tab.title
        setAccessibilityLabel(tab.title)
    }

    private func applyAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor(calibratedRed: 0.22, green: 0.40, blue: 0.85, alpha: 1.0).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            layer?.borderWidth = 1
            label.textColor = .white
            iconChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            iconChip.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
            iconView.contentTintColor = .white
        } else {
            layer?.backgroundColor = (
                isHovered ? NSColor.white.withAlphaComponent(0.05) : NSColor.clear
            ).cgColor
            layer?.borderWidth = 0
            label.textColor = NSColor.white.withAlphaComponent(0.82)
            iconChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            iconChip.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            iconView.contentTintColor = tab.iconTint
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearance()
    }

    func refreshHoverAtCurrentMouseLocation() {
        guard let window else {
            if isHovered {
                isHovered = false
                applyAppearance()
            }
            return
        }
        let mouseLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let shouldHighlight = visibleRect.contains(mouseLocation)
        guard isHovered != shouldHighlight else { return }
        isHovered = shouldHighlight
        applyAppearance()
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return sendAction(action, to: target)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Space || event.keyCode == kVK_Return {
            _ = accessibilityPerformPress()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

}

// MARK: - Action button (sidebar bottom row, mirrors TabButton's chrome)

private final class ActionButton: NSControl {
    private let iconChip = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var tint: NSColor = .systemGreen

    init(symbolName: String, title: String, tint: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        iconChip.translatesAutoresizingMaskIntoConstraints = false
        iconChip.wantsLayer = true
        iconChip.layer?.cornerRadius = 8
        iconChip.layer?.cornerCurve = .continuous
        iconChip.layer?.borderWidth = 1
        addSubview(iconChip)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown
        iconChip.addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),

            iconChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconChip.widthAnchor.constraint(equalToConstant: 28),
            iconChip.heightAnchor.constraint(equalToConstant: 28),

            iconView.centerXAnchor.constraint(equalTo: iconChip.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconChip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconChip.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        update(symbolName: symbolName, title: title, tint: tint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(symbolName: String, title: String, tint: NSColor) {
        self.tint = tint
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        label.stringValue = title
        applyAppearance()
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1.0 : 0.45 }
    }

    private func applyAppearance() {
        layer?.backgroundColor = NSColor.clear.cgColor
        // Match unselected TabButton's chip — the tint flows into the
        // icon glyph and the label so the whole row reads as a single color.
        iconChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        iconChip.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        iconView.contentTintColor = tint
        label.textColor = tint
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        sendAction(action, to: target)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    }

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEnabled, event.charactersIgnoringModifiers == "\r" {
            sendAction(action, to: target)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Settings tick slider

private final class SettingsTickSlider: NSControl {
    var minValue: Double
    var maxValue: Double
    var stepValue: Double
    var numberOfTickMarks: Int

    override var doubleValue: Double {
        get { value }
        set { setValue(newValue, notify: false) }
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isDragging = false
            }
            needsDisplay = true
        }
    }

    private var value: Double
    private var isDragging = false {
        didSet { needsDisplay = true }
    }

    private let knobSize = NSSize(width: 9, height: 18)
    private let trackHeight: CGFloat = 3.5
    private let tickDiameter: CGFloat = 2.5
    private let tickGap: CGFloat = 5
    private let accentColor = NSColor(
        calibratedRed: 0x11 / 255.0,
        green: 0x7D / 255.0,
        blue: 0xFF / 255.0,
        alpha: 1.0
    )

    init(
        frame: NSRect = .zero,
        value: Double,
        minValue: Double,
        maxValue: Double,
        stepValue: Double,
        numberOfTickMarks: Int,
        target: AnyObject?,
        action: Selector?
    ) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.stepValue = stepValue
        self.numberOfTickMarks = max(0, numberOfTickMarks)
        self.value = Self.normalizedValue(
            value,
            minValue: minValue,
            maxValue: maxValue,
            stepValue: stepValue
        )
        super.init(frame: frame)
        self.target = target
        self.action = action
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEnabled }

    override func draw(_ dirtyRect: NSRect) {
        let enabledAlpha: CGFloat = isEnabled ? 1 : 0.35
        let trackRect = NSRect(
            x: 0,
            y: floor(bounds.midY - trackHeight / 2),
            width: bounds.width,
            height: trackHeight
        )
        let travelRect = NSRect(
            x: knobSize.width / 2,
            y: trackRect.minY,
            width: max(1, bounds.width - knobSize.width),
            height: trackRect.height
        )

        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackHeight / 2,
            yRadius: trackHeight / 2
        )
        NSColor.white.withAlphaComponent(0.15 * enabledAlpha).setFill()
        trackPath.fill()

        let knobCenterX = travelRect.minX + normalizedFraction * travelRect.width
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(0, knobCenterX - trackRect.minX),
            height: trackRect.height
        )
        if fillRect.width > 0 {
            let fillPath = NSBezierPath(
                roundedRect: fillRect,
                xRadius: trackHeight / 2,
                yRadius: trackHeight / 2
            )
            accentColor.withAlphaComponent(enabledAlpha).setFill()
            fillPath.fill()
        }

        drawKnob(centerX: knobCenterX, enabledAlpha: enabledAlpha)
        drawTickMarks(in: travelRect, enabledAlpha: enabledAlpha)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isDragging = true
        updateValue(with: event, notify: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        updateValue(with: event, notify: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else {
            isDragging = false
            return
        }
        updateValue(with: event, notify: true)
        isDragging = false
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        let step = stepValue > 0 ? stepValue : (maxValue - minValue) / 10
        switch Int(event.keyCode) {
        case kVK_LeftArrow, kVK_DownArrow:
            setValue(value - step, notify: true)
        case kVK_RightArrow, kVK_UpArrow:
            setValue(value + step, notify: true)
        default:
            super.keyDown(with: event)
        }
    }

    private var normalizedFraction: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat((value - minValue) / (maxValue - minValue))
    }

    private func drawTickMarks(in trackRect: NSRect, enabledAlpha: CGFloat) {
        guard numberOfTickMarks > 1 else { return }
        let dotY = trackRect.minY - tickGap - tickDiameter
        for index in 0..<numberOfTickMarks {
            let fraction = CGFloat(index) / CGFloat(numberOfTickMarks - 1)
            let x = trackRect.minX + fraction * trackRect.width
            let tickRect = NSRect(
                x: x - tickDiameter / 2,
                y: dotY,
                width: tickDiameter,
                height: tickDiameter
            )
            NSColor.white.withAlphaComponent(0.24 * enabledAlpha).setFill()
            NSBezierPath(ovalIn: tickRect).fill()
        }
    }

    private func drawKnob(centerX: CGFloat, enabledAlpha: CGFloat) {
        let knobRect = NSRect(
            x: centerX - knobSize.width / 2,
            y: bounds.midY - knobSize.height / 2,
            width: knobSize.width,
            height: knobSize.height
        )
        let knobPath = NSBezierPath(
            roundedRect: knobRect,
            xRadius: knobSize.width / 2,
            yRadius: knobSize.width / 2
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18 * enabledAlpha)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor(white: isDragging ? 0.88 : 0.78, alpha: enabledAlpha).setFill()
        knobPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.18 * enabledAlpha).setStroke()
        knobPath.lineWidth = 0.5
        knobPath.stroke()
    }

    private func updateValue(with event: NSEvent, notify: Bool) {
        guard bounds.width > knobSize.width else { return }
        let location = convert(event.locationInWindow, from: nil)
        let trackMinX = knobSize.width / 2
        let trackWidth = max(1, bounds.width - knobSize.width)
        let fraction = min(max((location.x - trackMinX) / trackWidth, 0), 1)
        let newValue = minValue + Double(fraction) * (maxValue - minValue)
        setValue(newValue, notify: notify)
    }

    private func setValue(_ newValue: Double, notify: Bool) {
        let normalized = Self.normalizedValue(
            newValue,
            minValue: minValue,
            maxValue: maxValue,
            stepValue: stepValue
        )
        value = normalized
        needsDisplay = true
        if notify {
            sendAction(action, to: target)
        }
    }

    private static func normalizedValue(
        _ rawValue: Double,
        minValue: Double,
        maxValue: Double,
        stepValue: Double
    ) -> Double {
        let clamped = min(max(rawValue, minValue), maxValue)
        guard stepValue > 0 else { return clamped }
        let steps = ((clamped - minValue) / stepValue).rounded()
        let snapped = minValue + steps * stepValue
        return min(max(snapped, minValue), maxValue)
    }
}

// MARK: - Card view

/// Live preview of the window-capture shadow: a small window-like card
/// floating on a desktop-like backdrop. The shadow scales with `shadowSize`
/// so the user sees how high the captured window will appear to float.
private final class ShadowPreviewView: NSView {
    var shadowSize: CGFloat = 22 { didSet { needsDisplay = true } }
    var isEffectEnabled: Bool = true { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let backdrop = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        backdrop.addClip()

        // Desktop-like light backdrop so the dark shadow stays visible
        // (the settings UI itself is dark).
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.74, green: 0.78, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.60, green: 0.64, blue: 0.72, alpha: 1)
        ])
        gradient?.draw(in: bounds, angle: -90)

        // Window card geometry, centered; floats higher as the shadow grows.
        let cardW = min(bounds.width * 0.56, 210)
        let cardH: CGFloat = 64
        let lift = isEffectEnabled ? min(shadowSize, 60) * 0.10 : 0
        let cardRect = NSRect(
            x: ((bounds.width - cardW) / 2).rounded(),
            y: ((bounds.height - cardH) / 2 + lift).rounded(),
            width: cardW,
            height: cardH
        )
        let radius: CGFloat = 9
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)

        guard let ctx = NSGraphicsContext.current else { return }

        // Shadow pass. Scaled down relative to the real export — the preview
        // card is tiny — but proportional, so the slider's effect reads.
        ctx.saveGraphicsState()
        if isEffectEnabled, shadowSize > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
            shadow.shadowBlurRadius = shadowSize * 0.62
            shadow.shadowOffset = NSSize(width: 0, height: -shadowSize * 0.30)
            shadow.set()
        }
        NSColor.white.setFill()
        cardPath.fill()
        ctx.restoreGraphicsState()

        // Title-bar strip + traffic-light dots, clipped to the card.
        ctx.saveGraphicsState()
        cardPath.addClip()
        NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(
            x: cardRect.minX, y: cardRect.maxY - 16,
            width: cardRect.width, height: 16
        )).fill()
        let dotColors: [NSColor] = [
            NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.35, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.31, green: 0.79, blue: 0.31, alpha: 1)
        ]
        for (i, color) in dotColors.enumerated() {
            color.setFill()
            let d: CGFloat = 7
            NSBezierPath(ovalIn: NSRect(
                x: cardRect.minX + 9 + CGFloat(i) * 12,
                y: cardRect.maxY - 11.5, width: d, height: d
            )).fill()
        }
        ctx.restoreGraphicsState()

        // Hairline border for crispness.
        NSColor.black.withAlphaComponent(0.08).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()
    }
}

private final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1
    }
}

// MARK: - Status badge

final class StatusBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private var granted: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func configure(granted: Bool) {
        self.granted = granted
        refreshTitle()
    }

    func refreshTitle() {
        let color: NSColor = granted ? .systemGreen : .systemOrange
        label.stringValue = granted ? L10n.permissionGranted : L10n.permissionNotGranted
        label.textColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
    }
}

// MARK: - Hover button (clickable permission row)

private final class HoverButton: NSButton {
    var cornerRadius: CGFloat = 10 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.clear.cgColor
        (cell as? NSButtonCell)?.highlightsBy = []
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        super.mouseDown(with: event)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
    }
}
