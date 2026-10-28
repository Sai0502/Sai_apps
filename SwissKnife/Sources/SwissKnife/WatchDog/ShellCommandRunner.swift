import Foundation

struct CommandResult {
    let status: Int32
    let output: String
    let error: String
}

final class ShellCommandRunner: @unchecked Sendable {
    private let logger: EventLogger

    init(logger: EventLogger) {
        self.logger = logger
    }

    func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 10) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.log("COMMAND_START_FAILED executable=\(executable) error=\(error.localizedDescription)")
            return CommandResult(status: 127, output: "", error: error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            logger.log("COMMAND_TIMEOUT executable=\(executable) args=\(arguments.joined(separator: ","))")
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            status: process.terminationStatus,
            output: String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            error: String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
