import Foundation

/// 通用 JSON 配置文件存储：`Application Support/<directory>/settings.json`。
/// 供 Zone / Wheel 等模块复用，保留 `current` + `update` 的读写接口。
class JSONFileStore<T: Codable> {
    private let fileURL: URL
    private(set) var current: T

    init(directoryName: String, defaultValue: T) {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        fileURL = directory.appendingPathComponent("settings.json", isDirectory: false)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            current = decoded
        } else {
            current = defaultValue
            persist()
        }
    }

    func update(_ mutate: (inout T) -> Void) {
        mutate(&current)
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(current) {
            try? data.write(to: fileURL)
        }
    }
}
