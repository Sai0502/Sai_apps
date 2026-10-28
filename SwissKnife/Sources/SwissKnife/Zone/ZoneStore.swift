import Foundation

final class ZoneStore {
    static let shared = ZoneStore()

    private let fileURL: URL
    private(set) var current: ZoneSettings

    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseDirectory.appendingPathComponent("FitRecordZone", isDirectory: true)
        fileURL = directory.appendingPathComponent("settings.json", isDirectory: false)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(ZoneSettings.self, from: data)
        {
            current = decoded
        } else {
            current = ZoneSettings()
            persist()
        }
    }

    func update(_ mutate: (inout ZoneSettings) -> Void) {
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
