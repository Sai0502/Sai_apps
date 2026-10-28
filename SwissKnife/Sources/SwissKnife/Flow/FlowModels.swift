import Foundation
import SwiftUI

// MARK: - 阶段

enum Phase: String, CaseIterable, Identifiable {
    case flow
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flow: return "Flow"
        case .shortBreak: return "短休息"
        case .longBreak: return "长休息"
        }
    }

    var isBreak: Bool { self != .flow }
}

// MARK: - 计时状态

enum TimerStatus: Int {
    case idle
    case running
    case paused
}

// MARK: - 主题色（沿用 Flow 青绿风格）

enum Theme {
    static let flowColor = Color(red: 0.15, green: 0.47, blue: 0.40)   // #267866
    static let breakColor = Color(red: 0.78, green: 0.88, blue: 0.84)  // #C8E1D7
    static let accent = flowColor
}

// MARK: - 可用提示音

enum SoundName {
    /// 完成提示音可选列表（与 Resources/Sounds 现存文件一致；"无"用空字符串表示，由 UI 提供该选项）
    static let all: [String] = ["Bell", "Bowl", "Milestone"]
    static let defaultFlowSound = "Bell"
    static let defaultBreakSound = "Bowl"
}

// MARK: - 工具

func formattedTime(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%02d:%02d", m, sec)
}
