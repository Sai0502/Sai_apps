import Foundation

enum UploadError: LocalizedError {
    case missingConfig
    case invalidConfig(String)
    case network(String)
    case server(Int, String)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return L10n.uploadErrMissingConfig
        case .invalidConfig(let m):
            return "\(L10n.uploadErrInvalidConfigPrefix) \(m)"
        case .network(let m):
            return "\(L10n.uploadErrNetworkPrefix) \(m)"
        case .server(let code, let m):
            return "\(L10n.uploadErrServerPrefix(code)) \(m)"
        case .unexpectedResponse(let m):
            return "\(L10n.uploadErrUnexpectedResponsePrefix) \(m)"
        }
    }
}
