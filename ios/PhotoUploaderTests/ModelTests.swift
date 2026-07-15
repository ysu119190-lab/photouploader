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

    func testAlbumNameParsing() throws {
        XCTAssertEqual(
            try makePhoto(key: "uploads/sub/albums/家族旅行/2026/07/15/a.jpg").albumName,
            "家族旅行"
        )
        XCTAssertNil(try makePhoto(key: "uploads/sub/2026/07/15/a.jpg").albumName)
        XCTAssertNil(try makePhoto(key: "thumbs/sub/albums/x/a.jpg").albumName)
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
}
