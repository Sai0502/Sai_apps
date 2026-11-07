import AppKit
import CryptoKit

@MainActor
final class ClipboardMonitor {
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    var suppressUntilChangeCount: Int = -1

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        if current == suppressUntilChangeCount { return }
        guard let item = makeItem() else { return }
        ClipboardStore.shared.addCaptured(item)
    }

    private func makeItem() -> ClipItem? {
        let types = pasteboard.types ?? []

        // Everything is recorded, passwords included: this build is local-only and
        // never leaves the machine. Only transient drag data is skipped, because it
        // is not something the user ever meant to keep.
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) { return nil }

        let declaredSourceID = Self.validatedSourceBundleID(pasteboard.string(forType: Self.sourceType))
        let front = NSWorkspace.shared.frontmostApplication
        let src: NSRunningApplication?
        if front == nil || front?.bundleIdentifier == Bundle.main.bundleIdentifier {
            src = AppController.shared.lastActiveApp
        } else {
            src = front
        }
        let bundleID: String?
        let appName: String?
        if let declaredSourceID {
            bundleID = declaredSourceID
            appName = applicationName(forBundleID: declaredSourceID)
        } else {
            bundleID = src?.bundleIdentifier
            appName = src?.localizedName
        }

        func decorate(_ item: inout ClipItem) {
            item.sourceBundleID = bundleID
            item.sourceAppName = appName
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            var item = ClipItem(type: .file,
                                text: urls.map(\.lastPathComponent).joined(separator: ", "),
                                fileURLs: urls.map(\.absoluteString))
            decorate(&item)
            return item
        }

        if types.contains(.png) || types.contains(.tiff) {
            if let data = pngData() {
                let hash = Self.sha256Hex(data)
                guard let name = ClipboardStore.shared.storeImageData(data) else { return nil }
                var item = ClipItem(type: .image, imageFileName: name, imageHash: hash)
                decorate(&item)
                return item
            }
        }

        let rtf = pasteboard.data(forType: .rtf)
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let type: ClipType
            if rtf != nil {
                type = .richText
            } else if isLink(trimmed) {
                type = .link
            } else {
                type = .text
            }
            var item = ClipItem(type: type, text: string, rtfData: rtf)
            decorate(&item)
            return item
        }

        if hasColorType(types), let color = NSColor(from: pasteboard) {
            var item = ClipItem(type: .color, colorHex: color.usingColorSpace(.sRGB)?.hexString)
            decorate(&item)
            return item
        }

        return nil
    }

    private func hasColorType(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { $0.rawValue.localizedCaseInsensitiveContains("color") }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func pngData() -> Data? {
        if let data = pasteboard.data(forType: .png) { return data }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func validatedSourceBundleID(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= 255, raw.contains(".") else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return raw
    }

    private func applicationName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
    }

    private func isLink(_ s: String) -> Bool {
        guard !s.contains(" "), !s.contains("\n"),
              let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return false }
        return true
    }
}

private extension NSColor {
    convenience init?(from pasteboard: NSPasteboard) {
        guard let objs = pasteboard.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor],
              let c = objs.first else { return nil }
        self.init(cgColor: c.cgColor)
    }
}
