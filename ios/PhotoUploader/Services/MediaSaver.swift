import Foundation
import Photos

enum MediaSaverError: LocalizedError {
    case invalidURL
    case notAuthorized
    case downloadFailed(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "ダウンロードURLが不正です"
        case .notAuthorized:
            return "写真アプリへの追加が許可されていません。設定 > プライバシーとセキュリティ > 写真 から許可してください"
        case .downloadFailed(let status):
            return "ダウンロードに失敗しました (HTTP \(status))"
        }
    }
}

/// Downloads an uploaded photo/video via its presigned GET URL and saves it
/// back into the device photo library — the "restore" side of the backup.
enum MediaSaver {
    static func saveToPhotoLibrary(_ photo: RemotePhoto) async throws {
        guard let url = photo.imageURL else {
            throw MediaSaverError.invalidURL
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw MediaSaverError.notAuthorized
        }

        let (downloadedURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw MediaSaverError.downloadFailed(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }

        // Re-stage with the object key's extension so Photos recognizes the
        // format (the download temp file has none).
        let ext = (photo.key as NSString).pathExtension
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.moveItem(at: downloadedURL, to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(
                with: photo.isVideo ? .video : .photo,
                fileURL: staged,
                options: nil
            )
        }
    }
}
