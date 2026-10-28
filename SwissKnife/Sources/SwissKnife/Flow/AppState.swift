import Foundation
import AppKit
import SwiftUI
import ServiceManagement
import AVFoundation

/// 全局应用状态：计时引擎 + 设置持久化
@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    // MARK: - 计时状态

    @Published var phase: Phase = .flow
    @Published var status: TimerStatus = .idle
    @Published var remainingSeconds: Int = 25 * 60
    @Published var completedInCycle: Int = 0

    // MARK: - 时长设置

    @Published var flowMinutes: Int = 25 { didSet { save("flowMinutes", flowMinutes); applyDurationIfIdle() } }
    @Published var shortBreakMinutes: Int = 5 { didSet { save("shortBreakMinutes", shortBreakMinutes); applyDurationIfIdle() } }
    @Published var longBreakMinutes: Int = 15 { didSet { save("longBreakMinutes", longBreakMinutes); applyDurationIfIdle() } }
    @Published var sessionsBeforeLongBreak: Int = 4 { didSet { save("sessionsBeforeLongBreak", sessionsBeforeLongBreak) } }

    // MARK: - 自动行为设置

    @Published var launchAtLogin: Bool = false { didSet { save("launchAtLogin", launchAtLogin); updateLaunchAtLogin() } }
    @Published var startAtLaunch: Bool = false { didSet { save("startAtLaunch", startAtLaunch) } }
    @Published var commitmentMode: Bool = false { didSet { save("commitmentMode", commitmentMode) } }

    // 注：自动开始 Flow / 自动开始休息 / 休息开始时全屏 已按用户要求固定启用（见 flowCompleted 与 breakCompleted），不再提供设置项。

    // MARK: - 通知与声音设置

    @Published var notificationsEnabled: Bool = true { didSet { save("notificationsEnabled", notificationsEnabled) } }
    @Published var soundEnabled: Bool = true { didSet { save("soundEnabled", soundEnabled) } }
    @Published var notificationVolume: Double = 80 { didSet { save("notificationVolume", notificationVolume) } }
    @Published var tickingEnabled: Bool = false { didSet { save("tickingEnabled", tickingEnabled); syncTicking() } }
    @Published var flowCompleteSound: String = SoundName.defaultFlowSound { didSet { save("flowCompleteSound", flowCompleteSound) } }
    @Published var breakCompleteSound: String = SoundName.defaultBreakSound { didSet { save("breakCompleteSound", breakCompleteSound) } }
    @Published var endCountdownBeep: Bool = true { didSet { save("endCountdownBeep", endCountdownBeep) } }
    @Published var breakEndCountdownBeep: Bool = true { didSet { save("breakEndCountdownBeep", breakEndCountdownBeep) } }

    // MARK: - 内部

    private var timer: Timer?
    private var tickingPlayer: NSSound?
    lazy var notifications = NotificationsService()

    private init() {
        let d = UserDefaults.standard
        flowMinutes = d.integer(forKey: "flowMinutes") > 0 ? d.integer(forKey: "flowMinutes") : 25
        shortBreakMinutes = d.integer(forKey: "shortBreakMinutes") > 0 ? d.integer(forKey: "shortBreakMinutes") : 5
        longBreakMinutes = d.integer(forKey: "longBreakMinutes") > 0 ? d.integer(forKey: "longBreakMinutes") : 15
        sessionsBeforeLongBreak = d.integer(forKey: "sessionsBeforeLongBreak") > 0 ? d.integer(forKey: "sessionsBeforeLongBreak") : 4
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        startAtLaunch = d.bool(forKey: "startAtLaunch")
        commitmentMode = d.bool(forKey: "commitmentMode")
        notificationsEnabled = d.object(forKey: "notificationsEnabled") == nil ? true : d.bool(forKey: "notificationsEnabled")
        soundEnabled = d.object(forKey: "soundEnabled") == nil ? true : d.bool(forKey: "soundEnabled")
        notificationVolume = d.object(forKey: "notificationVolume") == nil ? 80 : d.double(forKey: "notificationVolume")
        tickingEnabled = d.bool(forKey: "tickingEnabled")
        // 修复：选「无」时保存的是空字符串，下次启动不能用 contains 误判回退默认音
        if let saved = d.string(forKey: "flowCompleteSound") {
            flowCompleteSound = saved.isEmpty || SoundName.all.contains(saved) ? saved : SoundName.defaultFlowSound
        } else {
            flowCompleteSound = SoundName.defaultFlowSound
        }
        if let saved = d.string(forKey: "breakCompleteSound") {
            breakCompleteSound = saved.isEmpty || SoundName.all.contains(saved) ? saved : SoundName.defaultBreakSound
        } else {
            breakCompleteSound = SoundName.defaultBreakSound
        }
        endCountdownBeep = d.object(forKey: "endCountdownBeep") == nil ? true : d.bool(forKey: "endCountdownBeep")
        breakEndCountdownBeep = d.object(forKey: "breakEndCountdownBeep") == nil ? true : d.bool(forKey: "breakEndCountdownBeep")
        remainingSeconds = duration(for: phase)
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - 时长

    func duration(for p: Phase) -> Int {
        switch p {
        case .flow: return flowMinutes * 60
        case .shortBreak: return shortBreakMinutes * 60
        case .longBreak: return longBreakMinutes * 60
        }
    }

    private func applyDurationIfIdle() {
        if status == .idle { remainingSeconds = duration(for: phase) }
    }

    // MARK: - 启动行为

    func handleLaunch() {
        if startAtLaunch {
            start()
        }
    }

    // MARK: - 计时控制

    func start() {
        guard status != .running else { return }
        if status == .idle {
            remainingSeconds = duration(for: phase)
        }
        status = .running
        startTickTimer()
        syncTicking()
    }

    func pause() {
        guard status == .running else { return }
        status = .paused
        stopTickTimer()
        stopTicking()
    }

    func resume() { start() }

    func stop() {
        guard !isCommitmentLocked else { return }
        status = .idle
        stopTickTimer()
        stopTicking()
        remainingSeconds = duration(for: phase)
        WindowManager.hideBreakOverlay()
    }

    func skip() {
        guard !isCommitmentLocked else { return }
        if phase.isBreak {
            WindowManager.hideBreakOverlay()
        }
        advanceToNextPhase()
    }

    func resetCurrent() {
        guard !isCommitmentLocked else { return }
        remainingSeconds = duration(for: phase)
        if status == .running {
            status = .running
        }
    }

    var isCommitmentLocked: Bool {
        commitmentMode && phase == .flow && status == .running
    }

    /// 当前阶段是否可被跳过/停止（承诺模式下锁定）
    var canSkipOrStop: Bool { !isCommitmentLocked }

    // MARK: - 引擎内部

    private func startTickTimer() {
        stopTickTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer 在 main runloop 触发，直接同步执行 tick
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopTickTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard status == .running else { return }
        remainingSeconds -= 1

        // Flow 最后 5 秒：每秒滴一声，提醒准备保存工作
        // 注：EndBeep 是单脉冲短音（0.2s），不会与上一声重叠
        if endCountdownBeep && phase == .flow && remainingSeconds <= 5 && remainingSeconds >= 1 && soundEnabled {
            SoundPlayer.shared.play("EndBeep", volume: Float(notificationVolume / 100))
        }

        // 休息最后 5 秒：每秒滴一声，提醒休息即将结束
        if breakEndCountdownBeep && phase.isBreak && remainingSeconds <= 5 && remainingSeconds >= 1 && soundEnabled {
            SoundPlayer.shared.play("EndBeep", volume: Float(notificationVolume / 100))
        }

        if remainingSeconds <= 0 {
            completePhase()
        }
    }

    private func completePhase() {
        stopTickTimer()
        stopTicking()

        if phase == .flow {
            completedInCycle += 1
            if completedInCycle >= sessionsBeforeLongBreak {
                completedInCycle = 0
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
            remainingSeconds = duration(for: phase)
            notifications.notifyFlowCompleted()
            if soundEnabled && !flowCompleteSound.isEmpty { SoundPlayer.shared.play(flowCompleteSound, volume: Float(notificationVolume / 100)) }
            // 固定行为：Flow 结束后全屏休息并自动开始休息计时（写死，不再提供设置项）
            WindowManager.showBreakOverlay()
            status = .idle
            start()
        } else {
            phase = .flow
            remainingSeconds = duration(for: phase)
            WindowManager.hideBreakOverlay()
            notifications.notifyBreakCompleted()
            if soundEnabled && !breakCompleteSound.isEmpty { SoundPlayer.shared.play(breakCompleteSound, volume: Float(notificationVolume / 100)) }
            // 固定行为：休息结束后自动开始 Flow（写死，不再提供设置项）
            status = .idle
            start()
        }
    }

    private func advanceToNextPhase() {
        stopTickTimer()
        stopTicking()
        if phase == .flow {
            completedInCycle += 1
            if completedInCycle >= sessionsBeforeLongBreak {
                completedInCycle = 0
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
            remainingSeconds = duration(for: phase)
            // 固定行为：Flow 结束后自动开始休息（写死，不再提供设置项）
            status = .idle
            start()
        } else {
            phase = .flow
            remainingSeconds = duration(for: phase)
            // 固定行为：休息结束后自动开始 Flow（写死，不再提供设置项）
            status = .idle
            start()
        }
    }

    // MARK: - 滴答声

    private func syncTicking() {
        if tickingEnabled && status == .running && phase == .flow {
            startTicking()
        } else {
            stopTicking()
        }
    }

    private func startTicking() {
        guard tickingPlayer == nil, let url = Bundle.main.url(forResource: "Ticking", withExtension: "wav") else { return }
        let s = NSSound(contentsOf: url, byReference: true)
        s?.volume = Float(notificationVolume / 100)
        s?.loops = true
        s?.play()
        tickingPlayer = s
    }

    private func stopTicking() {
        tickingPlayer?.stop()
        tickingPlayer = nil
    }

    // MARK: - 登录启动

    private func updateLaunchAtLogin() {
        LoginItemManager.setEnabled(launchAtLogin)
    }

    // MARK: - 调试信息

    /// 生成完整调试信息并复制到剪贴板，便于排查问题
    func copyDebugInfo() {
        let info = debugInfo()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info, forType: .string)
    }

    func debugInfo() -> String {
        var l: [String] = []
        l.append("Flow Clone v1.0.0 (local.flowclone.app)")
        l.append("生成时间: \(Date())")
        l.append("")
        l.append("【计时状态】")
        l.append("阶段: \(phase.displayName) (\(phase.rawValue))")
        let statusText: String
        switch status {
        case .idle: statusText = "待机"
        case .running: statusText = "运行中"
        case .paused: statusText = "已暂停"
        }
        l.append("状态: \(statusText)")
        l.append("剩余: \(remainingSeconds) 秒")
        l.append("周期进度: \(completedInCycle)/\(sessionsBeforeLongBreak)")
        l.append("承诺锁定中: \(isCommitmentLocked)")
        l.append("休息全屏遮罩: \(WindowManager.isBreakOverlayVisible ? "显示中" : "未显示")")
        l.append("")
        l.append("【时长设置】")
        l.append("Flow: \(flowMinutes) 分钟 | 短休: \(shortBreakMinutes) 分钟 | 长休: \(longBreakMinutes) 分钟")
        l.append("")
        l.append("【自动行为】")
        l.append("登录启动: \(launchAtLogin) | 启动即计时: \(startAtLaunch)")
        l.append("自动行为: 固定启用（自动开始Flow/自动开始休息/休息全屏）| 承诺模式: \(commitmentMode)")
        l.append("")
        l.append("【通知与声音】")
        l.append("通知: \(notificationsEnabled) | 声音: \(soundEnabled) | 音量: \(Int(notificationVolume))% | 滴答: \(tickingEnabled) | Flow结束前滴答: \(endCountdownBeep) | 休息结束前滴答: \(breakEndCountdownBeep)")
        l.append("Flow完成音: \(flowCompleteSound.isEmpty ? "无" : flowCompleteSound) | 休息完成音: \(breakCompleteSound.isEmpty ? "无" : breakCompleteSound)")
        let missing = SoundPlayer.shared.missingResources()
        l.append("提示音资源: \(missing.isEmpty ? "完整（\(SoundName.all.count) 个）" : "缺失：\(missing.joined(separator: ", "))")")
        l.append("")
        l.append("【系统】")
        l.append("系统版本: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        l.append("显示器: \(NSScreen.screens.count) 块")
        l.append("窗口列表: \(NSApp.windows.map { "\($0.title)@\($0.level.rawValue)" }.joined(separator: " | "))")
        return l.joined(separator: "\n")
    }
}

// MARK: - 登录启动

enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("登录启动设置失败: \(error)")
            }
        }
    }
}
