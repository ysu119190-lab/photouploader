import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import PhotoUploader

/// Pure-logic tests for the model layer (no network, no simulator UI).
final class ModelTests: XCTestCase {

    // MARK: RemotePhoto

    private func makePhoto(key: String, thumbnailUrl: String? = nil) throws -> RemotePhoto {
        var fields: [String: Any] = [
            "key": key,
            "size": 123,
            "lastModified": "2026-07-15T01:02:03+00:00",
            "url": "https://signed.example/get/\(key)",
        ]
        if let thumbnailUrl {
            fields["thumbnailUrl"] = thumbnailUrl
        }
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(RemotePhoto.self, from: data)
    }

    func testIsVideoByKeyExtension() throws {
        XCTAssertTrue(try makePhoto(key: "uploads/u/2026/07/15/a.mp4").isVideo)
        XCTAssertTrue(try makePhoto(key: "uploads/u/2026/07/15/a.MOV").isVideo)
        XCTAssertFalse(try makePhoto(key: "uploads/u/2026/07/15/a.jpg").isVideo)
        XCTAssertFalse(try makePhoto(key: "uploads/u/2026/07/15/a.heic").isVideo)
    }

    func testGridImageURLPrefersThumbnail() throws {
        let withThumb = try makePhoto(
            key: "uploads/u/a.jpg",
            thumbnailUrl: "https://signed.example/thumb.jpg"
        )
        XCTAssertEqual(withThumb.gridImageURL?.absoluteString, "https://signed.example/thumb.jpg")

        let withoutThumb = try makePhoto(key: "uploads/u/a.jpg")
        XCTAssertEqual(withoutThumb.gridImageURL, withoutThumb.imageURL)
    }

    func testPhotoListResponseDecodesWithoutOptionalFields() throws {
        // Older backends send neither albums nor thumbnailUrl — the app
        // must keep decoding their responses.
        let json = #"{"photos":[],"total":0,"nextOffset":null}"#
        let response = try JSONDecoder().decode(
            PhotoListResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(response.albums)
        XCTAssertNil(response.nextOffset)
    }

    // MARK: UploadItem persistence

    func testPersistedRoundTripKeepsTerminalStates() {
        var done = UploadItem(displayName: "写真 1")
        done.status = .done(key: "uploads/u/a.jpg")
        let restoredDone = UploadItem(restoring: done.persisted)
        guard case .done(let key) = restoredDone.status else {
            return XCTFail("done should restore as done")
        }
        XCTAssertEqual(key, "uploads/u/a.jpg")

        var failed = UploadItem(displayName: "写真 2")
        failed.status = .failed(message: "接続エラー")
        guard case .failed(let message) = UploadItem(restoring: failed.persisted).status else {
            return XCTFail("failed should restore as failed")
        }
        XCTAssertEqual(message, "接続エラー")
    }

    func testInFlightStatesRestoreAsInterrupted() {
        for status in [UploadItem.Status.pending, .uploading(progress: 0.4)] {
            var item = UploadItem(displayName: "写真")
            item.status = status
            guard case .interrupted = UploadItem(restoring: item.persisted).status else {
                return XCTFail("in-flight states must restore as interrupted")
            }
        }
    }

    func testSnapshotStoreRoundTrip() {
        defer { UploadItemsSnapshotStore.clear() }
        var item = UploadItem(displayName: "動画 1")
        item.status = .skipped
        UploadItemsSnapshotStore.save([item.persisted])

        let loaded = UploadItemsSnapshotStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].displayName, "動画 1")
        XCTAssertEqual(loaded[0].kind, .skipped)

        UploadItemsSnapshotStore.clear()
        XCTAssertTrue(UploadItemsSnapshotStore.load().isEmpty)
    }

    // MARK: Capture month (S3 folder)

    func testCaptureMonthFormatsInLocalCalendar() {
        var components = DateComponents()
        components.year = 2019
        components.month = 3
        components.day = 31
        components.hour = 23
        let date = Calendar.current.date(from: components)!
        XCTAssertEqual(UploadViewModel.captureMonth(of: date), "2019-03")
        XCTAssertNil(UploadViewModel.captureMonth(of: nil))
    }

    func testExifCaptureDateReadsDateTimeOriginal() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2021:11:05 08:30:00",
            ],
        ]
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let date = UploadViewModel.exifCaptureDate(of: data as Data)
        XCTAssertEqual(UploadViewModel.captureMonth(of: date), "2021-11")
        XCTAssertNil(UploadViewModel.exifCaptureDate(of: Data([0x00, 0x01])))
    }
}
