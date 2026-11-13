import AppKit

/// 断网提示：只负责响一声提醒用户，不做任何自动恢复动作。
final class NotificationManager {
    private static let alertSoundPath = "/System/Library/Sounds/Funk.aiff"

    func playOfflineAlert() {
        Task { @MainActor in
            guard let sound = NSSound(
                contentsOfFile: Self.alertSoundPath,
                byReference: true
            ) else {
                NSSound.beep()
                return
            }
            sound.play()
            // 保持引用直到播放结束，避免声音对象提前释放导致静音。
            try? await Task.sleep(
                nanoseconds: UInt64(max(sound.duration, 0.5) * 1_000_000_000)
            )
        }
    }
}
