import Foundation

enum TargetKind: String, Codable {
    case atas
    case parallels
}

struct TargetConfig: Codable {
    var enabled: Bool
    var scalePercent: Double

    init(enabled: Bool, scalePercent: Double) {
        self.enabled = enabled
        self.scalePercent = Self.clamp(scalePercent)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 100.0)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let raw = try container.decodeIfPresent(Double.self, forKey: .scalePercent) ?? 1.0
        scalePercent = Self.clamp(raw)
    }
}

struct WheelSettings: Codable {
    var atas = TargetConfig(enabled: true, scalePercent: 1.0)
    var parallels = TargetConfig(enabled: false, scalePercent: 1.0)

    subscript(kind: TargetKind) -> TargetConfig {
        get {
            switch kind {
            case .atas: return atas
            case .parallels: return parallels
            }
        }
        set {
            switch kind {
            case .atas: atas = newValue
            case .parallels: parallels = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case atas
        case parallels
        // 旧版单目标配置的字段，仅用于迁移读取
        case targetBundleID
        case scalePercent
        case scaleTenthsPercent
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let decoded = try container.decodeIfPresent(TargetConfig.self, forKey: .atas) {
            atas = decoded
        } else {
            // 兼容旧版：单一 scalePercent 迁移到 Atas
            var legacyScale = 1.0
            if let currentPercent = try container.decodeIfPresent(Double.self, forKey: .scalePercent) {
                legacyScale = min(max(currentPercent, 0.0), 100.0)
            } else if let legacyPercent = try container.decodeIfPresent(Int.self, forKey: .scalePercent) {
                legacyScale = min(max(Double(legacyPercent), 0.0), 100.0)
            } else if let tenths = try container.decodeIfPresent(Int.self, forKey: .scaleTenthsPercent) {
                legacyScale = min(max(Double(tenths) / 10.0, 0.0), 100.0)
            }
            atas = TargetConfig(enabled: true, scalePercent: legacyScale)
        }

        if let decoded = try container.decodeIfPresent(TargetConfig.self, forKey: .parallels) {
            parallels = decoded
        } else {
            parallels = TargetConfig(enabled: false, scalePercent: 1.0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(atas, forKey: .atas)
        try container.encode(parallels, forKey: .parallels)
    }
}

struct WheelEventSample: Codable {
    var at: Date
    var isContinuous: Bool
    var rawDeltaAxis1: Int64
    var rawDeltaAxis2: Int64
    var rawFixedAxis1: Double
    var rawFixedAxis2: Double
    var rawPointAxis1: Double
    var rawPointAxis2: Double
    var scaledDeltaAxis1: Int64
    var scaledDeltaAxis2: Int64
    var scaledFixedAxis1: Double
    var scaledFixedAxis2: Double
    var scaledPointAxis1: Double
    var scaledPointAxis2: Double
    var emittedLineAxis1: Int32
    var emittedLineAxis2: Int32
    var swallowedOriginalEvent: Bool
}

struct WheelTamerSnapshot: Codable {
    var generatedAt: Date
    var build: String
    var accessibilityTrusted: Bool
    var eventTapInstalled: Bool
    var eventTapEnabled: Bool
    var atasEnabled: Bool
    var atasScalePercent: Double
    var parallelsEnabled: Bool
    var parallelsScalePercent: Double
    var currentFrontmostBundleID: String
    var atasFrontmost: Bool
    var parallelsFrontmost: Bool
    var scaledEventCount: Int
    var observedEventCount: Int
    var lastEventSample: WheelEventSample?
    var logDirectory: String
}
