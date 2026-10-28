import Foundation

final class EventLogger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "network-watchdog.logger")
    private let formatter: DateFormatter
    private let dayFormatter: DateFormatter
    private let logDirectory: URL
    private var logFile: URL
    private var dayKey: String

    init(configuration: AppConfiguration) {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.formatter = formatter

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyyMMdd"
        self.dayFormatter = dayFormatter
        self.logDirectory = configuration.logDirectory
        self.dayKey = dayFormatter.string(from: now)
        self.logFile = configuration.logDirectory.appendingPathComponent(
            "network-watchdog-\(dayKey).log"
        )

        try? FileManager.default.createDirectory(
            at: configuration.logDirectory,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        scheduleNextRotation()
    }

    func log(_ message: String) {
        queue.async {
            let now = Date()
            self.rotateIfNeeded(at: now)
            let line = "[\(self.formatter.string(from: now))] \(message)\n"
            guard let newData = line.data(using: .utf8) else { return }
            let oldData = (try? Data(contentsOf: self.logFile)) ?? Data()

            var combinedData = Data()
            combinedData.reserveCapacity(newData.count + oldData.count)
            combinedData.append(newData)
            combinedData.append(oldData)
            try? combinedData.write(to: self.logFile, options: .atomic)
        }
    }

    func currentLogFileURL() -> URL {
        queue.sync { logFile }
    }

    private func scheduleNextRotation() {
        let now = Date()
        let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime,
            direction: .forward
        ) ?? now.addingTimeInterval(60)
        let delay = max(nextMidnight.timeIntervalSince(now), 1)

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.rotateIfNeeded(at: Date())
            self.scheduleNextRotation()
        }
    }

    private func rotateIfNeeded(at date: Date) {
        let newDayKey = dayFormatter.string(from: date)
        guard newDayKey != dayKey else { return }

        dayKey = newDayKey
        logFile = logDirectory.appendingPathComponent(
            "network-watchdog-\(newDayKey).log"
        )
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
    }
}
