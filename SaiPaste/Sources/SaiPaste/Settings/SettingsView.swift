import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        GeneralSettings()
            .frame(width: 520, height: 560)
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = Settings.shared
    @State private var accessibilityGranted = AccessibilityPermission.isTrusted

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("激活") {
                LabeledContent("显示 SaiPaste") { HotkeyRecorderView() }
            }

            HistoryRetentionSettings()

            Section("行为") {
                Toggle("始终以纯文本粘贴", isOn: $settings.pasteAsPlainText)
                Toggle("粘贴后把卡片移到最前", isOn: $settings.promoteOnPaste)
                Toggle("粘贴时播放声音", isOn: $settings.playSound)
                Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
                Toggle("显示面板拖动手柄", isOn: $settings.showBarResizeHandle)
            }

            Section("选择与导航") {
                Picker("选中卡片的位置", selection: $settings.selectedClipPosition) {
                    ForEach(SelectedClipPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.selectedClipPosition.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("权限") {
                HStack(spacing: 10) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("辅助功能")
                        Text(accessibilityGranted
                             ? "已授权，可以直接粘贴到当前光标位置。"
                             : "未授权，粘贴会退化为“复制到剪贴板”。请在系统设置 → 隐私与安全性 → 辅助功能中勾选 SaiPaste。授权后需重启 App 才生效。")
                            .font(.caption)
                            .foregroundStyle(accessibilityGranted ? .green : .secondary)
                    }
                    Spacer()
                    if accessibilityGranted {
                        Button("重启 SaiPaste") { AppController.restart() }
                    } else {
                        Button("打开系统设置") {
                            AccessibilityPermission.request(prompt: true)
                            AccessibilityPermission.openSettings()
                        }
                    }
                }
            }

            Section("数据") {
                Button("清空历史记录", role: .destructive) {
                    ClipboardStore.shared.clearHistory()
                }
                Text("删除后会立即清空，且不可恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityGranted = AccessibilityPermission.isTrusted }
        .onReceive(poll) { _ in
            let now = AccessibilityPermission.isTrusted
            if now != accessibilityGranted { accessibilityGranted = now }
        }
    }
}

private struct HistoryRetentionSettings: View {
    private var settings = Settings.shared
    @State private var draftMode = Settings.shared.historyRetentionMode
    @State private var draftLimit = Settings.shared.historyLimit
    @State private var draftDays = Settings.shared.historyRetentionDays
    @State private var pendingRemovalCount = 0
    @State private var confirmingChange = false
    @State private var storageBytes: Int64?

    @State private var sliderValue = HistoryRetentionPreset(nearestDays: Settings.shared.historyRetentionDays).sliderIndex
    @State private var sliderEditing = false

    private var sliderPreset: HistoryRetentionPreset { HistoryRetentionPreset(sliderIndex: sliderValue) }

    private var storageSummary: String {
        let count = ClipboardStore.shared.history.count
        let clips = "\(count) 条记录"
        guard let storageBytes else { return clips }
        return "\(clips) · \(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))"
    }

    private func refreshStorageSize() async {
        let dir = ClipboardStore.shared.dataDirectory
        storageBytes = await Task.detached(priority: .utility) {
            Self.directorySize(at: dir)
        }.value
    }

    /// Walks the store directory off the main actor; images can make it
    /// large enough that a synchronous walk would hitch the Settings window.
    nonisolated private static func directorySize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                              includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    var body: some View {
        Section {
            Picker("按什么保留历史", selection: $draftMode) {
                ForEach(HistoryRetentionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if draftMode == .itemCount {
                Stepper(value: $draftLimit, in: 50...5000, step: 50) {
                    LabeledContent("最多保留", value: "\(draftLimit) 条")
                }
            }
        } header: {
            Text("历史记录")
        } footer: {
            if draftMode != .itemCount {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("删除早于以下时间的内容")
                        Spacer()
                        Text(sliderPreset.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                    Slider(value: $sliderValue,
                           in: 0...Double(HistoryRetentionPreset.allCases.count - 1),
                           step: 1,
                           onEditingChanged: { editing in
                               sliderEditing = editing
                               if !editing { applySliderValue() }
                           })
                    HStack(spacing: 0) {
                        ForEach(HistoryRetentionPreset.allCases) { preset in
                            Text(preset.shortTitle)
                                .font(.system(size: 10, weight: preset == sliderPreset ? .bold : .medium))
                                .foregroundStyle(preset == sliderPreset ? Color.accentColor : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Text("只影响本机的历史记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, draftMode == .itemCount ? 0 : 4)
            LabeledContent("磁盘占用", value: storageSummary)
        }
        .task {
            await refreshStorageSize()
            for await _ in NotificationCenter.default.notifications(named: .saipasteStoreDidSave) {
                await refreshStorageSize()
            }
        }
        .onChange(of: draftMode) { evaluateDraft() }
        .onChange(of: draftLimit) { evaluateDraft() }
        .onChange(of: draftDays) { evaluateDraft() }
        .onChange(of: sliderValue) { if !sliderEditing { applySliderValue() } }
        .alert("将删除 \(pendingRemovalCount) 条记录", isPresented: $confirmingChange) {
            Button("删除 \(pendingRemovalCount) 条", role: .destructive) { commit() }
            Button("取消", role: .cancel) { revert() }
        } message: {
            Text("这个设置会立刻从本机历史中删除 \(pendingRemovalCount) 条记录，之后继续自动清理。此操作不可撤销。")
        }
    }

    private func evaluateDraft() {
        let count = ClipboardStore.shared.retentionRemovalCount(
            mode: draftMode, limit: draftLimit, days: draftDays)
        if count > 0 {
            pendingRemovalCount = count
            confirmingChange = true
        } else {
            commit()
        }
    }

    private func commit() {
        settings.historyRetentionMode = draftMode
        settings.historyLimit = draftLimit
        settings.historyRetentionDays = draftDays
        ClipboardStore.shared.applyRetentionPolicy()
    }

    private func revert() {
        draftMode = settings.historyRetentionMode
        draftLimit = settings.historyLimit
        draftDays = settings.historyRetentionDays
        sliderValue = HistoryRetentionPreset(nearestDays: draftDays).sliderIndex
    }

    private func applySliderValue() {
        let days = HistoryRetentionPreset(sliderIndex: sliderValue).days
        if days != draftDays { draftDays = days }
    }
}
