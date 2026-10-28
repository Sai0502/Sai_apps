import AppKit

final class NotificationManager {
    private static let manualAlertSoundPath = "/System/Library/Sounds/Funk.aiff"
    private let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func askDisableUSBAndUseWiFi(service: String?) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let wifiName = configuration.wifiName
        let serviceName = service ?? "iPhone USB"
        var accepted = false

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "USB 供网失败"
            alert.informativeText = "USB 供网仍未恢复。是否禁用 \"\(serviceName)\" 并尝试连接 Wi-Fi 热点 \"\(wifiName)\"？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "禁用 USB 并连接 Wi-Fi")
            alert.addButton(withTitle: "人工介入")
            accepted = alert.runModal() == .alertFirstButtonReturn
            semaphore.signal()
        }

        semaphore.wait()
        return accepted
    }

    func showManualConnectionAlert() {
        let wifiName = configuration.wifiName
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "网络恢复失败"
            alert.informativeText = "已断网，自动恢复失败，请手动连接热点 \"\(wifiName)\"。"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "去手动连接")
            alert.runModal()
        }
    }

    func playManualInterventionSound() {
        Task { @MainActor in
            let sound = NSSound(
                contentsOfFile: Self.manualAlertSoundPath,
                byReference: true
            )
            let interval = sound.map { max($0.duration + 0.15, 0.35) } ?? 0.75

            for index in 0..<3 {
                if let sound {
                    sound.play()
                } else {
                    NSSound.beep()
                }

                if index < 2 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(interval * 1_000_000_000)
                    )
                }
            }
        }
    }
}
