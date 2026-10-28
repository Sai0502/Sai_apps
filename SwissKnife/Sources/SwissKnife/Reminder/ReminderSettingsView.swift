import SwiftUI
import AppKit

// MARK: - 定时提醒设置

/// 设置面板「定时提醒」页签：5 条独立于 Flow 计时的到点提醒。
struct ReminderSettingsView: View {
    @ObservedObject var reminder = ReminderModule.shared

    var body: some View {
        Form {
            Section("定时播放") {
                ForEach($reminder.scheduledPlaybacks) { $item in
                    ScheduledPlaybackRow(item: $item)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 定时播放行

/// 定时播放设置行：时间（可清空，必选）+ 音频/视频 + 图片，行尾叉号一键全清
struct ScheduledPlaybackRow: View {
    @Binding var item: ScheduledPlayback

    private enum PickerKind { case av, image }

    /// 将小时/分钟映射为 Date，供 DatePicker 手动输入
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = item.hour
                comps.minute = item.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let cal = Calendar.current
                let h = cal.component(.hour, from: newDate)
                let m = cal.component(.minute, from: newDate)
                guard h != item.hour || m != item.minute else { return }
                item.hour = h
                item.minute = m
                item.lastTriggeredDay = nil   // 修改时间后允许当天再次触发
            }
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                timeControl
                    .frame(width: 150)
                avControl
                    .frame(width: 150, alignment: .leading)
                imageControl
                    .frame(width: 150, alignment: .leading)
                clearButton
            }
            weekControl
        }
    }

    // 星期条：周一~周日 7 个圆点，点选切换生效日（默认全选 = 每天；全不选 = 整行不触发）
    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    private var weekControl: some View {
        HStack(spacing: 6) {
            Text("生效日期")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()
            ForEach(0..<7, id: \.self) { i in
                Button {
                    item.weekdays[i].toggle()
                } label: {
                    Text(Self.weekdayLabels[i])
                        .font(.system(size: 13, weight: item.weekdays[i] ? .semibold : .regular))
                        .foregroundColor(item.weekdays[i] ? .white : .secondary)
                        .frame(width: 26, height: 26)
                        .background(item.weekdays[i] ? Color.accentColor : Color.gray.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("点选该行在一周的哪些天生效；全不选 = 整行不触发")
    }

    // 时间列：未设置 → 「设置时间…」；已设置 → 时间选择器
    @ViewBuilder private var timeControl: some View {
        if item.timeSet {
            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.stepperField)
                .labelsHidden()
        } else {
            Button("设置时间…") {
                let now = Date()
                let cal = Calendar.current
                item.hour = cal.component(.hour, from: now)
                item.minute = cal.component(.minute, from: now)
                item.timeSet = true
                item.lastTriggeredDay = nil
            }
        }
    }

    // 音频视频列：未选 → 「选择音/视频」；选中 → 只显示文件名（单行中段截断）
    @ViewBuilder private var avControl: some View {
        if item.avPath.isEmpty {
            Button("选择音/视频") { chooseFile(for: .av) }
        } else {
            Text(item.avFileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)
                .help(item.avPath)
        }
    }

    // 图片列：未选 → 「选择图片」；选中 → 只显示文件名（单行中段截断）
    @ViewBuilder private var imageControl: some View {
        if item.imagePath.isEmpty {
            Button("选择图片") { chooseFile(for: .image) }
        } else {
            Text(item.imageFileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)
                .help(item.imagePath)
        }
    }

    // 行尾叉号：一键清空 时间 + 音频视频 + 图片，整行恢复初始
    @ViewBuilder private var clearButton: some View {
        if item.timeSet || !item.avPath.isEmpty || !item.imagePath.isEmpty {
            Button {
                item.timeSet = false
                item.hour = 7
                item.minute = 0
                item.avPath = ""
                item.imagePath = ""
                item.lastTriggeredDay = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("清空整行（时间、音频视频、图片）")
        }
    }

    private func chooseFile(for kind: PickerKind) {
        let panel = NSOpenPanel()
        if kind == .av {
            panel.title = "选择音频或视频"
            panel.message = "音频在应用内播放；视频用系统默认播放器打开。"
        } else {
            panel.title = "选择图片"
            panel.message = "到点将全屏展示该图片 10 秒。"
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            if kind == .av {
                item.avPath = url.path
            } else {
                item.imagePath = url.path
            }
            item.lastTriggeredDay = nil
        }
    }
}
