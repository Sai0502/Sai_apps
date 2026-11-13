import Foundation

enum NetworkState: String, CaseIterable {
    case online = "Online"
    case verifying = "Verifying"
    case offline = "Offline"
}

enum NetworkEvent: String {
    case internetAvailable
    case internetLost
    case offlineConfirmed
}

@MainActor
protocol NetworkStateObserver: AnyObject {
    func networkStateDidChange(_ state: NetworkState)
}

final class NetworkStateMachine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "network-watchdog.state-machine")
    private var observers: [WeakStateObserver] = []
    private(set) var state: NetworkState = .online

    init() {}

    @MainActor
    func addObserver(_ observer: NetworkStateObserver) {
        observers.append(WeakStateObserver(observer))
    }

    func send(_ event: NetworkEvent) {
        queue.async {
            let newState = self.nextState(from: self.state, event: event)
            guard newState != self.state else { return }
            self.state = newState
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
        case (_, .internetAvailable):
            return .online
        case (.online, .internetLost):
            return .verifying
        case (.verifying, .offlineConfirmed), (.offline, .offlineConfirmed):
            return .offline
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
