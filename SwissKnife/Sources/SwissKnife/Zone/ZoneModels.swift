import AppKit
import Foundation

enum AppBuild {
    static let version = "FitRecordZone v2026_0722_131758"
}

struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.deviceRGB) ?? .white
        red = Double(color.redComponent)
        green = Double(color.greenComponent)
        blue = Double(color.blueComponent)
        alpha = Double(color.alphaComponent)
    }

    func nsColor() -> NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

struct ZoneSettings: Codable {
    var lastRatioText = "16:9"
    var lastFrameWidth: Double?
    var lastFrameHeight: Double?
    var strokeColor = CodableColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.78)
}

struct OverlaySnapshot: Codable {
    var visible: Bool
    var ratioText: String
    var ratioWidth: Double
    var ratioHeight: Double
    var frame: CodableRect?
    var screenName: String?
}

struct CodablePoint: Codable {
    var x: Double
    var y: Double

    init(_ point: NSPoint) {
        x = point.x
        y = point.y
    }
}

struct CodableSize: Codable {
    var width: Double
    var height: Double

    init(_ size: NSSize) {
        width = size.width
        height = size.height
    }
}

struct CodableRect: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

struct DebugSnapshot: Codable {
    var generatedAt: Date
    var build: String
    var settings: ZoneSettings
    var overlay: OverlaySnapshot?
    var mouseLocation: CodablePoint?
    var recentLogs: [String]
}

struct ParsedRatio {
    var text: String
    var width: CGFloat
    var height: CGFloat

    var value: CGFloat {
        width / height
    }

    static func from(size: NSSize) -> ParsedRatio {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        let divisor = greatestCommonDivisor(width, height)
        let normalizedWidth = max(width / max(divisor, 1), 1)
        let normalizedHeight = max(height / max(divisor, 1), 1)
        return ParsedRatio(
            text: "\(normalizedWidth):\(normalizedHeight)",
            width: CGFloat(normalizedWidth),
            height: CGFloat(normalizedHeight)
        )
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let remainder = x % y
            x = y
            y = remainder
        }
        return max(x, 1)
    }
}

enum OverlayChromeMetrics {
    static let leftInset: CGFloat = 44
    static let rightInset: CGFloat = 112
    static let topInset: CGFloat = 0
    static let bottomInset: CGFloat = 0
}

enum CornerHandle: String, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

enum ResizeMode: String, Codable {
    case fixedAspect
    case freeform
}

enum ResizeHandle: String, Codable {
    case bottomLeftAny
    case bottomRightFix

    var corner: CornerHandle {
        switch self {
        case .bottomLeftAny:
            return .bottomLeft
        case .bottomRightFix:
            return .bottomRight
        }
    }

    var mode: ResizeMode {
        switch self {
        case .bottomLeftAny:
            return .freeform
        case .bottomRightFix:
            return .fixedAspect
        }
    }
}

enum HitZone {
    case none
    case closeButton
    case move
    case resize(ResizeHandle)
}
