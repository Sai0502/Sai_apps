import Foundation

enum InterfaceType: String {
    case usb = "USB"
    case wifi = "WIFI"
    case none = "NONE"
    case other = "OTHER"
}

struct USBStatusSnapshot {
    let connected: Bool
    let interface: String?
    let service: String?
    let enabled: Bool
    let ipAddress: String?
    let gateway: String?
    let isDefaultRoute: Bool
}

final class NetworkInterfaceManager: @unchecked Sendable {
    private let shell: ShellCommandRunner

    init(shell: ShellCommandRunner) {
        self.shell = shell
    }

    func wifiInterface() -> String? {
        parseHardwarePorts().first { $0.port == "Wi-Fi" }?.device
    }

    func defaultInterface() -> String? {
        let output = shell.run("/sbin/route", ["-n", "get", "default"], timeout: 3).output
        return output.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.first == "interface" ? parts.last : nil
            }
            .first
    }

    func defaultGateway() -> String? {
        let output = shell.run("/sbin/route", ["-n", "get", "default"], timeout: 3).output
        return output.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.first == "gateway" ? parts.last : nil
            }
            .first
    }

    func ipv4Address(for interface: String?) -> String? {
        guard let interface, !interface.isEmpty else { return nil }
        let result = shell.run("/usr/sbin/ipconfig", ["getifaddr", interface], timeout: 3)
        return result.status == 0 && !result.output.isEmpty ? result.output : nil
    }

    func gateway(for interface: String?) -> String? {
        guard let interface, !interface.isEmpty else { return nil }
        let result = shell.run("/usr/sbin/ipconfig", ["getoption", interface, "router"], timeout: 3)
        return result.status == 0 && !result.output.isEmpty ? result.output : nil
    }

    func currentWiFiName(interface: String) -> String? {
        let summary = shell.run("/usr/sbin/ipconfig", ["getsummary", interface], timeout: 3).output
        if let ssid = summary.components(separatedBy: .newlines).compactMap({ line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("SSID") else { return nil }
            return trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        }).first, !ssid.isEmpty {
            return ssid
        }

        let airport = shell.run("/usr/sbin/networksetup", ["-getairportnetwork", interface], timeout: 3).output
        guard let separator = airport.firstIndex(of: ":") else { return nil }
        let name = airport[airport.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        return name.contains("not associated") || name.isEmpty ? nil : name
    }

    func interfaceType(_ interface: String?) -> InterfaceType {
        guard let interface, !interface.isEmpty else { return .none }
        if interface == wifiInterface() { return .wifi }
        guard let port = hardwarePort(for: interface)?.lowercased() else { return .other }
        return port.contains("iphone") && port.contains("usb") ? .usb : .other
    }

    func iPhoneUSBDeviceConnected() -> Bool {
        if iPhoneUSBInterface() != nil { return true }
        if interfaceType(defaultInterface()) == .usb { return true }
        let result = shell.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-l", "-w0"], timeout: 5)
        return result.output.range(of: "iPhone", options: .caseInsensitive) != nil
            || result.output.range(of: "SupportsIPhoneOS", options: .caseInsensitive) != nil
    }

    func iPhoneUSBInterface() -> String? {
        parseHardwarePorts().first { item in
            let port = item.port.lowercased()
            return port.contains("iphone") && port.contains("usb")
        }?.device
    }

    func networkService(for interface: String) -> String? {
        let output = shell.run("/usr/sbin/networksetup", ["-listnetworkserviceorder"], timeout: 5).output
        var currentService: String?
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("(") {
                let scanner = Scanner(string: line)
                _ = scanner.scanUpToString(")")
                _ = scanner.scanString(")")
                currentService = scanner.string[scanner.currentIndex...]
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "*", with: "")
            } else if line.contains("Device: \(interface)") {
                return currentService
            }
        }
        return nil
    }

    func networkServiceEnabled(_ service: String) -> Bool {
        let result = shell.run("/usr/sbin/networksetup", ["-getnetworkserviceenabled", service], timeout: 3)
        return result.output != "Disabled"
    }

    func setNetworkService(_ service: String, enabled: Bool) -> Bool {
        let result = shell.run("/usr/sbin/networksetup", ["-setnetworkserviceenabled", service, enabled ? "on" : "off"], timeout: 10)
        return result.status == 0
    }

    func linkIsActive(interface: String) -> Bool {
        shell.run("/sbin/ifconfig", [interface], timeout: 3).output.contains("status: active")
    }

    func usbSnapshot() -> USBStatusSnapshot {
        let route = defaultInterface()
        let defaultType = interfaceType(route)
        let usbInterface = iPhoneUSBInterface() ?? (defaultType == .usb ? route : nil)
        let service = usbInterface.flatMap { networkService(for: $0) }
        let connected = usbInterface != nil || defaultType == .usb
        let enabled = service.map { networkServiceEnabled($0) } ?? connected
        let ip = ipv4Address(for: usbInterface)
        return USBStatusSnapshot(
            connected: connected,
            interface: usbInterface,
            service: service,
            enabled: enabled,
            ipAddress: ip,
            gateway: gateway(for: usbInterface) ?? defaultGateway(),
            isDefaultRoute: route == usbInterface
        )
    }

    private func hardwarePort(for interface: String) -> String? {
        parseHardwarePorts().first { $0.device == interface }?.port
    }

    private func parseHardwarePorts() -> [(port: String, device: String)] {
        let output = shell.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 5).output
        var port = ""
        var result: [(String, String)] = []
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("Hardware Port:") {
                port = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:") {
                let device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                if !port.isEmpty && !device.isEmpty {
                    result.append((port, device))
                }
            }
        }
        return result
    }
}
