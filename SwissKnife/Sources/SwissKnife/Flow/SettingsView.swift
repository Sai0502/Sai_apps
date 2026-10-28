import SwiftUI

/// 设置面板（TabView：Flow / 附加功能）
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FlowSettingsView()
                .tabItem { Label("Flow", systemImage: "gearshape") }
                .tag(0)
            ReminderSettingsView()
                .tabItem { Label("定时提醒", systemImage: "sparkles") }
                .tag(1)
        }
        .frame(width: 580, height: 690)
    }
}

// MARK: - Flow 设置（原「常规/时长/通知与声音」合并为一个页签；
// 自动行为已固定启用、菜单栏图标已移除，不再提供设置项）

struct FlowSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动", isOn: $appState.launchAtLogin)
                Toggle("启动时开始计时", isOn: $appState.startAtLaunch)
            }

            Section("时长（分钟）") {
                Stepper("Flow：\(appState.flowMinutes) 分钟", value: $appState.flowMinutes, in: 1...180)
                Stepper("短休息：\(appState.shortBreakMinutes) 分钟", value: $appState.shortBreakMinutes, in: 1...60)
                Stepper("长休息：\(appState.longBreakMinutes) 分钟", value: $appState.longBreakMinutes, in: 1...120)
            }

            Section("周期") {
                Stepper("每 \(appState.sessionsBeforeLongBreak) 个 Flow 后长休息", value: $appState.sessionsBeforeLongBreak, in: 1...12)
                Text("完成指定数量的 Flow 后，将进入一次长休息。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("通知") {
                Toggle("允许通知", isOn: $appState.notificationsEnabled)
                Toggle("声音通知", isOn: $appState.soundEnabled)
            }

            Section("音量与滴答") {
                HStack {
                    Text("通知音量")
                    Slider(value: $appState.notificationVolume, in: 0...100, step: 5)
                        .frame(maxWidth: 260)
                    Text("\(Int(appState.notificationVolume))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Toggle("滴答声（Flow 进行中）", isOn: $appState.tickingEnabled)
                Toggle("Flow 结束前 5 秒滴答提示", isOn: $appState.endCountdownBeep)
                Text("每个 Flow 最后 5 秒每秒滴一声，提醒你及时保存工作。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("休息结束前 5 秒滴答提示", isOn: $appState.breakEndCountdownBeep)
                Text("每次休息最后 5 秒每秒滴一声，提醒休息即将结束。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("完成提示音") {
                Picker("Flow 完成", selection: $appState.flowCompleteSound) {
                    Text("无").tag("")
                    ForEach(SoundName.all, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Picker("休息完成", selection: $appState.breakCompleteSound) {
                    Text("无").tag("")
                    ForEach(SoundName.all, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            Section {
                Toggle("承诺模式", isOn: $appState.commitmentMode)
                Text("开启后，Flow 进行中无法停止或跳过，强制完成本次专注。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("专注")
            }
        }
        .formStyle(.grouped)
    }
}
