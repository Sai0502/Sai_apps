import XCTest
@testable import SaiPaste

@MainActor
final class ClipPreviewProviderTests: XCTestCase {
    func testOnlySingleImageFilesShowAsImages() {
        let png = ClipItem(type: .file, fileURLs: ["file:///tmp/shot.png"])
        let pdf = ClipItem(type: .file, fileURLs: ["file:///tmp/report.pdf"])
        let two = ClipItem(type: .file, fileURLs: ["file:///tmp/a.png", "file:///tmp/b.png"])

        XCTAssertEqual(ClipPreviewProvider.imageFileURL(for: png)?.path, "/tmp/shot.png")
        XCTAssertNil(ClipPreviewProvider.imageFileURL(for: pdf))
        XCTAssertNil(ClipPreviewProvider.imageFileURL(for: two))
        XCTAssertTrue(ClipPreviewProvider.showsImage(ClipItem(type: .image, imageFileName: "x.png")))
        XCTAssertFalse(ClipPreviewProvider.showsImage(pdf))
    }

    func testFileInfoReportsMissingFilesOnlyOnENOENT() async {
        let present = ClipItem(type: .file, fileURLs: ["file:///bin/ls"])
        let gone = ClipItem(type: .file, fileURLs: ["file:///nonexistent/\(UUID().uuidString).pdf"])

        let presentInfo = await ClipPreviewProvider.fileInfo(for: present)
        XCTAssertEqual(presentInfo?.isMissing, false)
        XCTAssertNotNil(presentInfo?.icon)

        let goneInfo = await ClipPreviewProvider.fileInfo(for: gone)
        // The App Store (sandboxed) build is gone, so a file that is not there
        // is always reported as missing.
        XCTAssertEqual(goneInfo?.isMissing, true)
        XCTAssertNotNil(goneInfo?.icon)

        let text = await ClipPreviewProvider.fileInfo(for: ClipItem(type: .text, text: "x"))
        XCTAssertNil(text)
    }
}
