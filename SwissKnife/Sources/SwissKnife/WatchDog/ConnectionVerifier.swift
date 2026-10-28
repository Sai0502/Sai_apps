import Foundation

final class ConnectionVerifier {
    private let configuration: AppConfiguration
    private let internetChecker: InternetChecker
    private let interfaceManager: NetworkInterfaceManager
    private let logger: EventLogger

    init(
        configuration: AppConfiguration,
        internetChecker: InternetChecker,
        interfaceManager: NetworkInterfaceManager,
        logger: EventLogger
    ) {
        self.configuration = configuration
        self.internetChecker = internetChecker
        self.interfaceManager = interfaceManager
        self.logger = logger
    }

    func waitForWiFi(interface: String) -> Bool {
        var second = 1
        var waitLimit = configuration.connectVerifySeconds
        var progressGraceApplied = false

        while second <= waitLimit {
            Thread.sleep(forTimeInterval: 1)
            let wifiName = interfaceManager.currentWiFiName(interface: interface)
            let ipv4 = interfaceManager.ipv4Address(for: interface)
            let defaultInterface = interfaceManager.defaultInterface()
            let linkActive = interfaceManager.linkIsActive(interface: interface)

            if internetChecker.isReachable() {
                if wifiName == configuration.wifiName,
                   hasValidIPv4(ipv4),
                   defaultInterface == interface {
                    logger.log("WIFI_RECOVERED wait=\(second)s interface=\(interface) network=\(configuration.wifiName) ipv4=\(ipv4 ?? "none") internet=ok")
                } else {
                    logger.log("INTERNET_RECOVERED wait=\(second)s interface=\(defaultInterface ?? "unknown") wifi=\(wifiName ?? "none") action=stop_recovery")
                }
                return true
            }

            if second >= configuration.connectVerifySeconds && !progressGraceApplied {
                if linkActive || hasValidIPv4(ipv4) || defaultInterface == interface {
                    waitLimit = configuration.connectVerifySeconds + configuration.connectProgressGraceSeconds
                    progressGraceApplied = true
                    logger.log("WIFI_PROGRESS interface=\(interface) network=\(configuration.wifiName) link=\(yesNo(linkActive)) ipv4=\(ipv4 ?? "none") route_interface=\(defaultInterface ?? "none") action=extend_wait extended_limit=\(waitLimit)s")
                }
            }

            logger.log("WIFI_VERIFY wait=\(second)/\(waitLimit) link=\(yesNo(linkActive)) associated=\(yesNo(wifiName == configuration.wifiName)) ipv4=\(yesNo(hasValidIPv4(ipv4))) route=\(yesNo(defaultInterface == interface)) internet=no interface=\(interface) network=\(configuration.wifiName)")
            second += 1
        }

        return false
    }
}

final class USBConnectionVerifier {
    private let configuration: AppConfiguration
    private let internetChecker: InternetChecker
    private let interfaceManager: NetworkInterfaceManager
    private let logger: EventLogger

    init(
        configuration: AppConfiguration,
        internetChecker: InternetChecker,
        interfaceManager: NetworkInterfaceManager,
        logger: EventLogger
    ) {
        self.configuration = configuration
        self.internetChecker = internetChecker
        self.interfaceManager = interfaceManager
        self.logger = logger
    }

    func waitForUSB(interface: String) -> Bool {
        var second = 1
        var waitLimit = configuration.usbVerifySeconds
        var progressGraceApplied = false

        while second <= waitLimit {
            Thread.sleep(forTimeInterval: 1)
            let ipv4 = interfaceManager.ipv4Address(for: interface)
            let defaultInterface = interfaceManager.defaultInterface()
            let gateway = interfaceManager.defaultGateway()
            let linkActive = interfaceManager.linkIsActive(interface: interface)

            if internetChecker.isReachable() {
                if defaultInterface == interface {
                    logger.log("USB_RECOVERED wait=\(second)s interface=\(interface) ipv4=\(ipv4 ?? "none") gateway=\(gateway ?? "none") internet=ok")
                } else {
                    logger.log("INTERNET_RECOVERED wait=\(second)s interface=\(defaultInterface ?? "unknown") action=stop_usb_recovery")
                }
                return true
            }

            if second >= configuration.usbVerifySeconds && !progressGraceApplied {
                if linkActive || hasValidIPv4(ipv4) || defaultInterface == interface {
                    waitLimit = configuration.usbVerifySeconds + configuration.usbProgressGraceSeconds
                    progressGraceApplied = true
                    logger.log("USB_PROGRESS interface=\(interface) link=\(yesNo(linkActive)) ipv4=\(ipv4 ?? "none") route_interface=\(defaultInterface ?? "none") action=extend_wait extended_limit=\(waitLimit)s")
                }
            }

            logger.log("USB_VERIFY wait=\(second)/\(waitLimit) link=\(yesNo(linkActive)) ipv4=\(yesNo(hasValidIPv4(ipv4))) route=\(yesNo(defaultInterface == interface)) internet=no interface=\(interface)")
            second += 1
        }

        return false
    }
}

func hasValidIPv4(_ address: String?) -> Bool {
    guard let address, !address.isEmpty else { return false }
    return !address.hasPrefix("169.254.")
}

func yesNo(_ value: Bool) -> String {
    value ? "yes" : "no"
}
