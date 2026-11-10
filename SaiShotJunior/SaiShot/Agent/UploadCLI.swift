import Foundation

/// `<app> upload <image> [image ...]` — uploads images to the GitHub picbed
/// configured in `~/.github-picbed.json` and prints one URL per line.
///
/// Typora's "custom command" upload service appends the image path to the
/// command and reads stdout as the image URL, so this prints nothing else.
enum UploadCLI {
    static func runIfRequested(arguments: [String]) -> Int32? {
        guard arguments.first == "upload" else { return nil }

        var filePaths: [String] = []
        for argument in arguments.dropFirst() {
            if argument.hasPrefix("--") || argument.hasPrefix("-") { continue }
            filePaths.append(argument)
        }

        guard !filePaths.isEmpty else {
            let usage = "usage: \(AppIdentity.executableName) upload <image> [...]\n"
            FileHandle.standardError.write(Data(usage.utf8))
            return 2
        }

        let config: PicbedConfig
        do {
            config = try PicbedConfig.load()
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }

        var exitCode: Int32 = 0
        for path in filePaths {
            let fileURL = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: fileURL) else {
                FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
                exitCode = 1
                continue
            }
            do {
                let url = try GitHubPicbedUploader.upload(
                    data: data,
                    fileName: fileURL.lastPathComponent,
                    config: config
                )
                print(url.absoluteString)
            } catch {
                FileHandle.standardError.write(Data("upload failed for \(path): \(error.localizedDescription)\n".utf8))
                exitCode = 1
            }
        }
        return exitCode
    }
}
