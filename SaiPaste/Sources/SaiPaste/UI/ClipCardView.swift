import AppKit
import ImageIO
import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let selected: Bool

    @State private var hovering = false
    @State private var preview: NSImage?
    @State private var previewFailed = false
    @State private var fileInfo: ClipPreviewProvider.FileInfo?
    private var store: ClipboardStore { ClipboardStore.shared }
    private var settings: Settings { Settings.shared }
    private var headerColor: Color { SourceColor.color(for: item.sourceBundleID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            body_
        }
        .frame(width: Theme.cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .background {
            if selected {
                RoundedRectangle(
                    cornerRadius: Theme.cardCorner + Theme.selectedCardRing,
                    style: .continuous
                )
                .fill(Theme.selection)
                .padding(-Theme.selectedCardRing)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(selected ? Theme.selection : Theme.cardBorder,
                              lineWidth: selected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .scaleEffect(hovering && !selected ? 1.015 : 1.0)
        .zIndex(selected ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: selected)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .contentShape(Rectangle())
        .overlay {
            ClickCatcher { clickCount, modifiers in
                handleClick(count: clickCount, modifiers: modifiers)
            } onHoverChange: { hovering = $0 }
        }
        .task(id: item.id) { await loadPreview() }
    }

    /// Single click selects right away, a second click pastes. Both are
    /// decided from `clickCount`, so nothing waits out the double-click interval.
    private func handleClick(count: Int, modifiers: NSEvent.ModifierFlags) {
        BarLog.log.log("card click id=\(self.item.id, privacy: .public) count=\(count, privacy: .public) shift=\(modifiers.contains(.shift), privacy: .public)")
        if modifiers.contains(.shift) {
            store.extendSelection(to: item.id)
            AppController.shared.focusCards()
            return
        }
        if count >= 2 {
            AppController.shared.pasteItem(item)
            return
        }
        store.select(item.id)
        AppController.shared.focusCards()
    }

    private var header: some View {
        ZStack {
            headerColor
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardTypeLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.headerText)
                    Text(item.createdAt.clipRelativeLong)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.headerSubText)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                appIconTile
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
        }
        .frame(height: Theme.headerHeight)
    }

    private var cardTypeLabel: String {
        if item.type == .file, item.fileURLs.count > 1 { return "\(item.fileURLs.count) 个文件" }
        return item.type.label
    }

    private var appIconTile: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.white.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14))
            )
            .frame(width: 56, height: 56)
            .overlay(
                Image(nsImage: AppIconProvider.icon(forBundleID: item.sourceBundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
            )
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, showsImage ? 0 : 13)
                .padding(.top, showsImage ? 0 : 11)
            footer
                .padding(.horizontal, 13)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardBody)
    }

    /// Image clips, and file clips pointing at an image, which is how a copied
    /// screenshot usually arrives, run edge to edge instead of sitting inset.
    private var showsImage: Bool {
        ClipPreviewProvider.showsImage(item) && !previewFailed
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            imageCanvas
        case .color:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: NSColor(hex: item.colorHex ?? "#000") ?? .black))
                Text(item.colorHex ?? "")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white).shadow(radius: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .file:
            if showsImage {
                imageCanvas
            } else {
                fileContent
            }
        case .link:
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "safari").font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.cardTextTertiary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        default:
            Text(item.text ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.cardTextPrimary.opacity(0.9))
                .lineLimit(10)
                .multilineTextAlignment(.leading)
        }
    }

    /// Over a checkerboard, so a transparent cut-out is distinguishable from
    /// an image on white.
    private var imageCanvas: some View {
        ZStack {
            CheckerboardBackground()
            if let image = preview ?? ClipPreviewProvider.cachedImage(for: item) {
                Image(nsImage: image)
                    .resizable().interpolation(.medium).scaledToFit()
            } else {
                placeholder("photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var fileContent: some View {
        VStack(spacing: 9) {
            if let icon = fileInfo?.icon ?? ClipPreviewProvider.cachedIcon(for: item) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Theme.fileIconSize, height: Theme.fileIconSize)
                    .opacity(fileInfo?.isMissing == true ? 0.5 : 1)
            } else {
                Image(systemName: "doc.fill").font(.system(size: 32))
                    .foregroundStyle(headerColor)
            }
            Text(item.displayTitle).font(.system(size: 12))
                .foregroundStyle(Theme.cardTextSecondary).lineLimit(2)
                .multilineTextAlignment(.center)
            if fileInfo?.isMissing == true {
                Text("文件不存在")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.cardTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadPreview() async {
        preview = ClipPreviewProvider.cachedImage(for: item)
        fileInfo = nil
        previewFailed = false
        if ClipPreviewProvider.showsImage(item) {
            if preview == nil {
                preview = await ClipPreviewProvider.image(for: item, scale: NSScreen.main?.backingScaleFactor ?? 2)
            }
            guard preview == nil, item.type == .file else { return }
            previewFailed = true
        }
        guard item.type == .file else { return }
        fileInfo = await ClipPreviewProvider.fileInfo(for: item)
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 30))
            .foregroundStyle(Theme.cardTextTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if item.type == .link {
                Text(item.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.cardTextPrimary).lineLimit(1)
            }
            HStack(alignment: .bottom, spacing: 6) {
                // A path is worth reading in full, so it wraps rather than
                // collapsing to an ellipsis; everything else stays one line.
                Text(metaLeft)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.cardTextSecondary)
                    .lineLimit(item.type == .file ? 3 : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
            }
        }
        .padding(.top, 8)
    }

    private var isSingleImageFile: Bool {
        ClipPreviewProvider.imageFileURL(for: item) != nil
    }

    /// NSHomeDirectory is the sandbox container in the App Store build, so the
    /// real home comes from the account record instead.
    private static let homePath: String = {
        if let home = getpwuid(getuid())?.pointee.pw_dir { return String(cString: home) }
        return NSHomeDirectory()
    }()

    private static func abbreviatedPath(_ path: String) -> String {
        if path == homePath { return "~" }
        guard path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    private var metaLeft: String {
        switch item.type {
        case .text, .richText:
            return "\(item.charCount) 个字符"
        case .link:
            return (item.text ?? "").replacingOccurrences(of: "https://", with: "")
                                    .replacingOccurrences(of: "http://", with: "")
        case .file:
            guard item.fileURLs.count == 1,
                  let url = item.fileURLs.first.flatMap(URL.init(string:)) else {
                return item.fileURLs
                    .compactMap { URL(string: $0)?.lastPathComponent }
                    .joined(separator: ", ")
            }
            // An image shows what it is, so its size is the useful fact; a
            // screenshot's path is a timestamped folder nobody reads. Files
            // without a preview get the full location instead, since two
            // documents of the same name differ only by where they live.
            if isSingleImageFile {
                guard let size = ImagePixelSize.of(url) else { return url.lastPathComponent }
                return "\(Int(size.width)) × \(Int(size.height))"
            }
            return Self.abbreviatedPath(url.path)
        case .image:
            guard let size = ImagePixelSize.of(item) else { return "图片" }
            return "\(Int(size.width)) × \(Int(size.height))"
        case .color:
            return item.colorHex ?? "颜色"
        }
    }

}

/// The standard transparency checkerboard drawn behind image clips. A Canvas
/// rather than a tiled image: the pattern is a handful of rects, and this keeps
/// it resolution independent without shipping an asset.
private struct CheckerboardBackground: View {
    var square: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let columns = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            for row in 0..<max(rows, 0) {
                for column in 0..<max(columns, 0) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * square,
                                      y: CGFloat(row) * square,
                                      width: square,
                                      height: square)
                    context.fill(Path(rect), with: .color(Color(white: 0.87)))
                }
            }
        }
        .drawingGroup()
    }
}

/// Reads an image clip's pixel dimensions from the file's metadata instead of
/// decoding it, and remembers them: the card footer asks on every render.
@MainActor
enum ImagePixelSize {
    private static var cache: [String: CGSize?] = [:]
    private static let cacheLimit = 512

    static func of(_ item: ClipItem) -> CGSize? {
        guard item.imageFileName != nil,
              let url = ClipboardStore.shared.imageURL(for: item) else { return nil }
        return of(url)
    }

    static func of(_ url: URL) -> CGSize? {
        let name = url.path
        if let cached = cache[name] { return cached }
        if cache.count >= cacheLimit { cache.removeAll() }
        let size = read(url)
        cache.updateValue(size, forKey: name)
        return size
    }

    private static func read(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
}
