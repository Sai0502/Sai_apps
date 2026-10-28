import Foundation

final class WheelStore {
    static let shared = WheelStore()

    private let fileURL: URL
    private(set) var current: WheelSettings

    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseDirectory.appendingPathComponent("ATASWheelTamer", isDirectory: true)
        fileURL = directory.appendingPathComponent("settings.json", isDirectory: false)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(WheelSettings.self, from: data)
        {
            current = decoded
        } else {
            current = WheelSettings()
            persist()
        }
    }

    func update(_ mutate: (inout WheelSettings) -> Void) {
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
