import Foundation

/// GitHub-picbed settings shared by the app and the `SaiShot upload` CLI.
/// The file lives at `~/.github-picbed.json` so Typora's custom command and
/// this binary read exactly the same configuration.
struct PicbedConfig: Codable, Equatable {
    var repo: String
    var branch: String
    var path: String
    var customUrl: String
    var token: String

    enum LoadError: LocalizedError {
        case missingFile(String)
        case incomplete(String)

        var errorDescription: String? {
            switch self {
            case .missingFile(let path):
                return "picbed config not found: \(path)"
            case .incomplete(let detail):
                return "picbed config incomplete: \(detail)"
            }
        }
    }

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".github-picbed.json")
    }

    static func load(from url: URL = defaultFileURL) throws -> PicbedConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.missingFile(url.path)
        }
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(PicbedConfig.self, from: data)

        let trimmedRepo = config.repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = config.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepo.isEmpty, trimmedRepo.contains("/") else {
            throw LoadError.incomplete("repo must be owner/name")
        }
        guard !trimmedToken.isEmpty else {
            throw LoadError.incomplete("token is empty")
        }
        return config
    }

    /// Directory prefix, always with exactly one trailing slash.
    var normalizedDirectory: String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "img/" : trimmed
        return base.hasSuffix("/") ? base : base + "/"
    }

    var branchOrDefault: String {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "master" : trimmed
    }

    func publicURL(forRemotePath remotePath: String) -> String {
        let encoded = remotePath
            .split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")

        let custom = customUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return custom.hasSuffix("/") ? custom + encoded : custom + "/" + encoded
        }
        return "https://raw.githubusercontent.com/\(repo)/\(branchOrDefault)/\(encoded)"
    }

    /// Mirrors PicGo's `autoRename`: a timestamp prefix keeps uploads from
    /// overwriting earlier images with the same local file name.
    func remotePath(for fileName: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        let stamp = formatter.string(from: date)

        var base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        base = sanitized(base)
        if base.isEmpty { base = "image" }

        let suffix = ext.isEmpty ? "" : "." + sanitized(ext)
        return normalizedDirectory + stamp + "-" + base + suffix
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let mapped = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
