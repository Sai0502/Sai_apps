import Foundation

final class InternetChecker: @unchecked Sendable {
    private let configuration: AppConfiguration
    private let session: URLSession

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 1
        sessionConfiguration.timeoutIntervalForResource = 1.2
        // 不复用任何缓存/凭据：否则断网后仍会命中上次成功的缓存响应，误判为在线。
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCredentialStorage = nil
        self.session = URLSession(configuration: sessionConfiguration)
    }

    func isReachable() -> Bool {
        latencyMilliseconds() != nil
    }

    func latencyMilliseconds() -> Int? {
        for url in configuration.testURLs {
            if let latency = probe(url) {
                return latency
            }
        }
        return nil
    }

    private func probe(_ url: URL) -> Int? {
        let start = Date()
        let semaphore = DispatchSemaphore(value: 0)
        let result = ProbeResult()

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request) { _, response, error in
            if error == nil, let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                result.markSuccess()
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.3)
        task.cancel()

        guard result.success else { return nil }
        return max(1, Int(Date().timeIntervalSince(start) * 1000))
    }
}

private final class ProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var success: Bool {
        lock.withLock { value }
    }

    func markSuccess() {
        lock.withLock { value = true }
    }
}
