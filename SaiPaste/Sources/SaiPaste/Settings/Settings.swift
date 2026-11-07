import AppKit
import Carbon.HIToolbox
import Observation

enum HistoryRetentionMode: String, CaseIterable, Identifiable {
    case itemCount
    case timeInterval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .itemCount: return "按条数"
        case .timeInterval: return "按天数"
        }
    }
}

/// The discrete stops on the time-based retention slider. `historyRetentionDays`
/// stays the underlying source of truth (a raw day count, with 0 meaning
/// "forever" - never prune by age) - this just names the stops so the slider
/// can snap between them instead of offering a raw number field.
enum HistoryRetentionPreset: Int, CaseIterable, Identifiable {
    case day
    case week
    case twoWeeks
    case threeWeeks
    case month
    case twoMonths
    case threeMonths
    case sixMonths
    case year
    case forever

    var id: Int { rawValue }

    /// 0 means forever - no automatic time-based pruning.
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .twoWeeks: return 14
        case .threeWeeks: return 21
        case .month: return 30
        case .twoMonths: return 60
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        case .forever: return 0
        }
    }

    var title: String {
        switch self {
        case .day: return "1 天"
        case .week: return "1 周"
        case .twoWeeks: return "2 周"
        case .threeWeeks: return "3 周"
        case .month: return "1 个月"
        case .twoMonths: return "2 个月"
        case .threeMonths: return "3 个月"
        case .sixMonths: return "6 个月"
        case .year: return "1 年"
        case .forever: return "永久"
        }
    }

    var shortTitle: String {
        switch self {
        case .day: return "1d"
        case .week: return "1w"
        case .twoWeeks: return "2w"
        case .threeWeeks: return "3w"
        case .month: return "1m"
        case .twoMonths: return "2m"
        case .threeMonths: return "3m"
        case .sixMonths: return "6m"
        case .year: return "1y"
        case .forever: return "∞"
        }
    }

    var sliderIndex: Double { Double(rawValue) }

    /// Snaps an arbitrary day count (including ones from before this preset
    /// set existed) to its nearest stop, so old UserDefaults values still
    /// land on a sensible position on the slider.
    init(nearestDays days: Int) {
        self = Self.allCases.min(by: { abs($0.days - days) < abs($1.days - days) }) ?? .month
    }

    init(sliderIndex: Double) {
        let index = min(Self.allCases.count - 1, max(0, Int(sliderIndex.rounded())))
        self = Self.allCases[index]
    }
}

enum SelectedClipPosition: Int, CaseIterable, Identifiable {
    case center
    case rightEdge

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .center: "居中"
        case .rightEdge: "靠右"
        }
    }

    var detail: String {
        switch self {
        case .center: "选中卡片居中显示，左右保留上下文。"
        case .rightEdge: "选中卡片贴到最右侧，与 Paste 一致。"
        }
    }
}

@Observable
@MainActor
final class Settings {
    static let shared = Settings()

    @ObservationIgnored private let d = UserDefaults.standard
    @ObservationIgnored private var isLoaded = false

    enum Keys {
        static let historyLimit = "historyLimit"
        static let historyRetentionMode = "historyRetentionMode"
        static let historyRetentionDays = "historyRetentionDays"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let playSound = "playSound"
        static let promoteOnPaste = "promoteOnPaste"
        static let pasteAsPlainText = "pasteAsPlainText"
        static let barHeight = "barHeight"
        static let showBarResizeHandle = "showBarResizeHandle"
        static let selectedClipPosition = "selectedClipPosition"
    }

    var historyLimit: Int {
        didSet {
            guard isLoaded else { return }
            if historyLimit < 20 { historyLimit = 20; return }
            d.set(historyLimit, forKey: Keys.historyLimit)
        }
    }

    var historyRetentionMode: HistoryRetentionMode {
        didSet {
            guard isLoaded else { return }
            d.set(historyRetentionMode.rawValue, forKey: Keys.historyRetentionMode)
        }
    }

    /// A raw day count for time-based pruning; 0 means forever (no automatic
    /// pruning by age). See `HistoryRetentionPreset` for the named stops the
    /// Settings slider snaps this to.
    var historyRetentionDays: Int {
        didSet {
            guard isLoaded else { return }
            if historyRetentionDays < 0 { historyRetentionDays = 0; return }
            d.set(historyRetentionDays, forKey: Keys.historyRetentionDays)
        }
    }

    var hotkeyKeyCode: Int {
        didSet { guard isLoaded else { return }
            d.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode); HotKeyCenter.shared.reload() }
    }

    var hotkeyModifiers: Int {
        didSet { guard isLoaded else { return }
            d.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers); HotKeyCenter.shared.reload() }
    }

    var launchAtLogin: Bool {
        didSet { guard isLoaded else { return }
            d.set(launchAtLogin, forKey: Keys.launchAtLogin); LaunchAtLogin.set(enabled: launchAtLogin) }
    }

    var playSound: Bool {
        didSet { guard isLoaded else { return }; d.set(playSound, forKey: Keys.playSound) }
    }

    /// Pasting a clip moves it to the front of history the way copying it
    /// from the bar does. Off by default: history has always been ordered by
    /// when a clip was copied, and ordering by paste order would shuffle the
    /// strip on every paste.
    var promoteOnPaste: Bool {
        didSet { guard isLoaded else { return }; d.set(promoteOnPaste, forKey: Keys.promoteOnPaste) }
    }

    /// Paste every clip without its original formatting, the way Paste's
    /// "always paste as plain text" option does.
    var pasteAsPlainText: Bool {
        didSet { guard isLoaded else { return }; d.set(pasteAsPlainText, forKey: Keys.pasteAsPlainText) }
    }

    var barHeight: Double {
        didSet {
            guard isLoaded else { return }
            let normalized = BarResizeGeometry.normalizedPersistedHeight(barHeight)
            if normalized != barHeight { barHeight = normalized; return }
            d.set(barHeight, forKey: Keys.barHeight)
        }
    }

    var showBarResizeHandle: Bool {
        didSet {
            guard isLoaded else { return }
            d.set(showBarResizeHandle, forKey: Keys.showBarResizeHandle)
        }
    }

    var selectedClipPosition: SelectedClipPosition {
        didSet { guard isLoaded else { return }; d.set(selectedClipPosition.rawValue, forKey: Keys.selectedClipPosition) }
    }

    private init() {
        d.register(defaults: [
            Keys.historyLimit: 500,
            Keys.historyRetentionMode: HistoryRetentionMode.itemCount.rawValue,
            Keys.historyRetentionDays: 30,
            Keys.hotkeyKeyCode: kVK_ANSI_V,
            Keys.hotkeyModifiers: cmdKey | shiftKey,
            Keys.launchAtLogin: false,
            Keys.playSound: false,
            Keys.promoteOnPaste: false,
            Keys.pasteAsPlainText: false,
            Keys.barHeight: BarResizeGeometry.defaultHeight,
            Keys.showBarResizeHandle: false,
            Keys.selectedClipPosition: SelectedClipPosition.center.rawValue
        ])
        historyLimit = d.integer(forKey: Keys.historyLimit)
        historyRetentionMode = HistoryRetentionMode(rawValue: d.string(forKey: Keys.historyRetentionMode) ?? "")
            ?? .itemCount
        historyRetentionDays = max(0, d.integer(forKey: Keys.historyRetentionDays))
        hotkeyKeyCode = d.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = d.integer(forKey: Keys.hotkeyModifiers)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        playSound = d.bool(forKey: Keys.playSound)
        promoteOnPaste = d.bool(forKey: Keys.promoteOnPaste)
        pasteAsPlainText = d.bool(forKey: Keys.pasteAsPlainText)
        let storedBarHeight = d.double(forKey: Keys.barHeight)
        let normalizedBarHeight = BarResizeGeometry.normalizedPersistedHeight(storedBarHeight)
        barHeight = normalizedBarHeight
        showBarResizeHandle = d.bool(forKey: Keys.showBarResizeHandle)
        selectedClipPosition = SelectedClipPosition(rawValue: d.integer(forKey: Keys.selectedClipPosition)) ?? .center
        isLoaded = true
        if normalizedBarHeight != storedBarHeight {
            d.set(normalizedBarHeight, forKey: Keys.barHeight)
        }
    }

    var hotkeyDisplay: String {
        HotKeyCenter.describe(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }
}
