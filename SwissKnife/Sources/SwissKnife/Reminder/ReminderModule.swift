import AppKit
import SwiftUI
import AVFoundation

/// Reminder（定时提醒）模块：独立的到点提醒，与 Flow 番茄钟计时引擎完全解耦。
/// 负责：5 条「时间 + 音视频/图片」配置的持久化、秒级调度、到点触发（浮层/全屏图片/音视频播放）。
@MainActor
final class ReminderModule: ObservableObject {
    static let shared = ReminderModule()

    // MARK: - 状态

    /// 最多 5 组「时间 + 内容」的定时播放
    @Published var scheduledPlaybacks: [ScheduledPlayback] = [] {
        didSet { saveScheduledPlaybacks() }
    }

    // MARK: - 内部

    private var scheduleTimer: Timer?
    private var audioPlayers: [AVAudioPlayer] = []   // 持有音频播放器引用，防止播放被提前释放
    private var lastWarnedRem: Int?                  // 上一轮预警剩余秒数（避免重复滴答）
    private var cancelPendingTrigger = false          // 预警圆圈双击后，取消本次到点触发

    private init() {
        scheduledPlaybacks = loadScheduledPlaybacks()
    }

    // MARK: - 生命周期

    func start() {
        startScheduleTimer()
    }

    func stop() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
    }

    // MARK: - 持久化

    /// 持久化读取：固定 10 行（id 0–9），缺失行自动补默认值（兼容旧 5 行配置）
    private func loadScheduledPlaybacks() -> [ScheduledPlayback] {
        guard let data = UserDefaults.standard.data(forKey: "scheduledPlaybacks"),
              let items = try? JSONDecoder().decode([ScheduledPlayback].self, from: data) else {
            return (0..<10).map { ScheduledPlayback(id: $0) }
        }
        return (0..<10).map { id in items.first(where: { $0.id == id }) ?? ScheduledPlayback(id: id) }
    }

    private func saveScheduledPlaybacks() {
        guard let data = try? JSONEncoder().encode(scheduledPlaybacks) else { return }
        UserDefaults.standard.set(data, forKey: "scheduledPlaybacks")
    }

    // MARK: - 调度

    /// 秒级检查（每秒一次）：
    /// - 到点前 5 秒：滴答预警 + 主屏右上角倒计时浮层（所有组合都有）
    /// - 到点（HH:MM:00）：触发提醒，同一天不重复；与 Flow 计时状态无关
    private func startScheduleTimer() {
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkScheduledPlaybacks() }
        }
    }

    private func checkScheduledPlaybacks() {
        guard scheduledPlaybacks.contains(where: { $0.isConfigured }) else { return }
        let now = Date()
        let cal = Calendar.current
        let day = Self.dayKey(now)
        var minWarnRem: Int? = nil

        for i in scheduledPlaybacks.indices {
            var item = scheduledPlaybacks[i]
            guard item.isConfigured else { continue }
            guard item.isActiveToday else { continue }   // 今天不在生效星期内：本行不预警、不触发

            // 目标时间 = 今天 hour:minute:00
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = item.hour
            comps.minute = item.minute
            comps.second = 0
            guard let target = cal.date(from: comps) else { continue }

            // 剩余秒数（向上取整）：1...5 为预警窗口，<=0 为到点
            let rem = Int(ceil(target.timeIntervalSince(now)))
            if rem >= 1 && rem <= 5 {
                minWarnRem = min(minWarnRem ?? rem, rem)
            }
            if rem <= 0 && item.lastTriggeredDay != day {
                item.lastTriggeredDay = day
                scheduledPlaybacks[i] = item
                if cancelPendingTrigger {
                    NSLog("定时提醒：双击取消本次触发 %@", item.timeText)
                } else {
                    triggerScheduledPlayback(item)
                }
            }
        }

        // 预警：剩余秒数变化时滴一声并更新角落倒计时
        let volume = Float(AppState.shared.notificationVolume / 100)
        if let rem = minWarnRem, rem != lastWarnedRem {
            lastWarnedRem = rem
            if AppState.shared.soundEnabled {
                SoundPlayer.shared.play("EndBeep", volume: volume)
            }
            ReminderWindowManager.showCountdownOverlay(rem) { [weak self] in
                self?.cancelPendingTrigger = true
                ReminderWindowManager.hideCountdownOverlay()
            }
        } else if minWarnRem == nil, lastWarnedRem != nil {
            lastWarnedRem = nil
            cancelPendingTrigger = false
            ReminderWindowManager.hideCountdownOverlay()
        }
    }

    /// 到点触发：
    /// - 选了图片 → 所有屏幕全屏展示图片（含 10 秒倒计时与「跳过」按钮）
    /// - 选了音频/视频 → 音频应用内播放 / 视频用系统默认播放器打开
    private func triggerScheduledPlayback(_ item: ScheduledPlayback) {
        let hasAV = !item.avPath.isEmpty
        let hasImage = !item.imagePath.isEmpty
        NSLog("定时提醒：触发提醒 %@（音视频:%@，图片:%@）", item.timeText,
              hasAV ? item.avPath : "无", hasImage ? item.imagePath : "无")

        if hasImage {
            if let image = loadImage(item.imagePath) {
                ReminderWindowManager.showScheduledImageOverlay(image: image)
            } else {
                NSLog("定时提醒：图片加载失败 %@", item.imagePath)
            }
        }

        if hasAV {
            playScheduledAV(item.avPath)
        }
    }

    /// 播放音频/视频：按扩展名区分，视频调起系统默认播放器，其余应用内播放
    private func playScheduledAV(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("定时提醒：文件不存在，已跳过 %@", path)
            return
        }
        if Self.isVideoFile(path) {
            NSWorkspace.shared.open(url)
            NSLog("定时提醒：已用系统默认播放器打开视频 %@", path)
        } else {
            playScheduledAudio(url)
        }
    }

    private func loadImage(_ path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private static func isVideoFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        let videos = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv", "mpg", "mpeg", "3gp", "ts", "m2ts", "vob", "ogv", "rm", "rmvb"]
        return videos.contains(ext)
    }

    /// 应用内播放音频（跟随通知音量，类似滴答声）
    private func playScheduledAudio(_ url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(AppState.shared.notificationVolume / 100)
            player.play()
            audioPlayers.append(player)
            let duration = player.duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.0) { [weak self] in
                self?.audioPlayers.removeAll { $0 === player }
            }
            NSLog("定时提醒：应用内播放音频 %@", url.path)
        } catch {
            NSLog("定时提醒：音频播放失败 %@，%@", url.path, error.localizedDescription)
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    // MARK: - 调试信息

    /// 四合一调试快照的 Reminder 段
    func debugSummary() -> String {
        let scheduled = scheduledPlaybacks.map { item -> String in
            guard item.timeSet else { return "未设置时间" }
            var parts = [item.timeText]
            if !item.avPath.isEmpty { parts.append("音视频:\(item.avPath)") }
            if !item.imagePath.isEmpty { parts.append("图片:\(item.imagePath)") }
            return parts.joined(separator: " | ")
        }.joined(separator: " || ")
        return "定时提醒: \(scheduled)"
    }
}
