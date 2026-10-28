import Foundation

enum NetworkState: String, CaseIterable {
    case online = "Online"
    case verifying = "Verifying"
    case offline = "Offline"
    case recoveringUSB = "USB Recovery"
    case recoveringWiFi = "WiFi Recovery"
    case waitingManual = "Manual Recovery"
}

enum NetworkEvent: String {
    case internetAvailable
    case internetLost
    case offlineConfirmed
    case usbRecoveryStarted
    case usbRecoverySucceeded
    case usbRecoveryFailed
    case wifiRecoveryStarted
    case wifiRecoverySucceeded
    case wifiRecoveryFailed
    case manualRequired
}

@MainActor
protocol NetworkStateObserver: AnyObject {
    func networkStateDidChange(_ state: NetworkState)
}

final class NetworkStateMachine: @unchecked Sendable {
    private let logger: EventLogger
    private let queue = DispatchQueue(label: "network-watchdog.state-machine")
    private var observers: [WeakStateObserver] = []
    private(set) var state: NetworkState = .online

    init(logger: EventLogger) {
        self.logger = logger
    }

    @MainActor
    func addObserver(_ observer: NetworkStateObserver) {
        observers.append(WeakStateObserver(observer))
    }

    func send(_ event: NetworkEvent) {
        queue.async {
            let oldState = self.state
            let newState = self.nextState(from: oldState, event: event)
            guard newState != oldState else { return }
            self.state = newState
            self.logger.log("STATE from=\(oldState.rawValue.replacingOccurrences(of: " ", with: "_")) event=\(event.rawValue) to=\(newState.rawValue.replacingOccurrences(of: " ", with: "_"))")
            Task { @MainActor in
                self.notify(newState)
            }
        }
    }

    func currentState() -> NetworkState {
        queue.sync { state }
    }

    private func nextState(from state: NetworkState, event: NetworkEvent) -> NetworkState {
        switch (state, event) {
        case (_, .internetAvailable), (_, .usbRecoverySucceeded), (_, .wifiRecoverySucceeded):
            return .online
        case (.online, .internetLost):
            return .verifying
        case (.verifying, .offlineConfirmed):
            return .offline
        case (.offline, .usbRecoveryStarted):
            return .recoveringUSB
        case (.offline, .wifiRecoveryStarted), (.recoveringUSB, .wifiRecoveryStarted):
            return .recoveringWiFi
        case (.recoveringUSB, .usbRecoveryFailed):
            return .offline
        case (.recoveringWiFi, .wifiRecoveryFailed), (_, .manualRequired):
            return .waitingManual
        case (.waitingManual, .internetLost):
            return .waitingManual
        default:
            return state
        }
    }

    @MainActor
    private func notify(_ state: NetworkState) {
        observers = observers.filter { $0.observer != nil }
        observers.forEach { $0.observer?.networkStateDidChange(state) }
    }
}

private final class WeakStateObserver: @unchecked Sendable {
    weak var observer: NetworkStateObserver?

    init(_ observer: NetworkStateObserver) {
        self.observer = observer
    }
}
