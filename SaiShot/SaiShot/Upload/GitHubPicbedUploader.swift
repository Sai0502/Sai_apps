import Foundation

/// Uploads an image into a GitHub repository through the Contents API and
/// returns its public URL. Same behaviour as the PicGo GitHub uploader it
/// replaces: base64 body, timestamped file name, configurable branch/path.
enum GitHubPicbedUploader {
    /// Uploads `data` and returns the public URL. Blocking, so it can be used
    /// from the CLI; the app can call it from a background task.
    static func upload(
        data: Data,
        fileName: String,
        config: PicbedConfig
    ) throws -> URL {
        let remotePath = config.remotePath(for: fileName)

        var components = URLComponents(string: "https://api.github.com")!
        components.path = "/repos/\(config.repo)/contents/" + remotePath
        guard let endpoint = components.url else {
            throw PicbedConfig.LoadError.incomplete("bad repo path")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "message": "upload \(fileName)",
            "branch": config.branchOrDefault,
            "content": data.base64EncodedString(),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 45

        let (responseData, response) = try synchronousSend(request)

        guard let http = response as? HTTPURLResponse else {
            throw PicbedConfig.LoadError.incomplete("no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw UploadError.server(http.statusCode, String(body.prefix(200)))
        }

        guard let url = URL(string: config.publicURL(forRemotePath: remotePath)) else {
            throw PicbedConfig.LoadError.incomplete("bad public URL")
        }
        return url
    }

    /// Runs the request on a semaphore so callers stay synchronous (CLI) without
    /// forcing an async rewrite of the surrounding code.
    private static func synchronousSend(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>?

        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success((data ?? Data(), response ?? URLResponse()))
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()

        switch result {
        case .success(let value): return value
        case .failure(let error): throw UploadError.network(error.localizedDescription)
        case nil: throw UploadError.network("request never completed")
        }
    }
}
