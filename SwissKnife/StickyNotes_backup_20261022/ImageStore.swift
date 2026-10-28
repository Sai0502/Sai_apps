import AppKit

/// 便签内嵌图片的文件存储。
/// 图片统一存为 PNG 到 ~/Library/Application Support/SwissKnife/StickyNotes/images/<uuid>.png
final class ImageStore {
    static let shared = ImageStore()

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwissKnife/StickyNotes/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func fileURL(for file: String) -> URL {
        dir.appendingPathComponent(file)
    }

    /// 把剪贴板/粘贴得到的 NSImage 写入磁盘, 返回 (uuid, 文件名, 宽高比)。
    /// 写入失败返回 nil (调用方保持原文本不插入 token)。
    func save(_ image: NSImage) -> (id: String, file: String, ratio: CGFloat)? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let id = UUID().uuidString
        let file = "\(id).png"
        do {
            try data.write(to: fileURL(for: file), options: .atomic)
            let size = rep.pixelsWide > 0 && rep.pixelsHigh > 0
                ? CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                : CGSize(width: 1, height: 1)
            let ratio = size.height > 0 ? CGFloat(size.width) / CGFloat(size.height) : 1
            return (id, file, ratio)
        } catch {
            return nil
        }
    }

    /// 加载图片 (编辑器渲染用), 找不到返回 nil
    func load(_ file: String) -> NSImage? {
        NSImage(contentsOf: fileURL(for: file))
    }

    func deleteFile(_ file: String) {
        try? FileManager.default.removeItem(at: fileURL(for: file))
    }

    /// 删除 images/ 目录中不在引用集合里的孤儿文件
    func pruneOrphans(used: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "png" {
            let name = url.lastPathComponent
            if !used.contains(name) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
