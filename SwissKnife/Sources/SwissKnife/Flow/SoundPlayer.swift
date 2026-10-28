import Foundation
import AppKit

/// 提示音播放器
final class SoundPlayer {
    static let shared = SoundPlayer()

    func play(_ name: String, volume: Float = 0.8) {
        guard !name.isEmpty else { return }   // "无"：不播放任何提示音
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            NSLog("找不到声音资源: %@", name)
            return
        }
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.volume = min(max(volume, 0), 1)
            sound.play()
        }
    }

    /// 检查提示音资源是否完整（调试用）
    func missingResources() -> [String] {
        SoundName.all.filter { Bundle.main.url(forResource: $0, withExtension: "wav") == nil }
    }
}
