import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class UploadViewModel: ObservableObject {
    /// Photos in the current (or most recent) batch.
    @Published private(set) var items: [UploadItem] = []
    @Published private(set) var isUploading = false
    /// One-shot notice for the user (e.g. "nothing new to back up").
    @Published var infoMessage: String?
    /// Finished batches, newest first, persisted across launches.
    @Published private(set) var history: [UploadBatchSummary] = UploadHistoryStore.load()

    init() {
        // Restore the last batch's rows so a relaunch doesn't blank the
        // screen; rows that were mid-flight come back as "interrupted".
        items = UploadItemsSnapshotStore.load().map(UploadItem.init(restoring:))
    }

    var doneCount: Int {
        items.filter { if case .done = $0.status { return true } else { return false } }.count
    }

    var skippedCount: Int {
        items.filter { if case .skipped = $0.status { return true } else { return false } }.count
    }

    var failedCount: Int {
        items.filter { if case .failed = $0.status { return true } else { return false } }.count
    }

    /// How many photos are prepared and uploaded at the same time. Raising
    /// this speeds up large batches but increases memory and network pressure.
    private let maxConcurrentUploads = 4

    /// Image MIME types the backend accepts as-is; other images are re-encoded to JPEG.
    private static let supportedMimeTypes: Set<String> = [
        "image/jpeg", "image/png", "image/heic", "image/heif", "image/webp", "image/gif",
    ]

    /// Video MIME types the backend accepts. Unlike images there is no
    /// re-encode fallback — transcoding video on device is too slow.
    private static let supportedVideoMimeTypes: Set<String> = [
        "video/mp4", "video/quicktime", "video/x-m4v",
    ]

    /// Uploads the picked photos as one batch, at most `maxConcurrentUploads`
    /// at a time. Once a photo is handed to the background session, its
    /// transfer survives backgrounding; this method only needs the app alive
    /// while photos are being read from the photo library and prepared.
    func handleSelection(_ pickerItems: [PhotosPickerItem]) async {
        guard !pickerItems.isEmpty, !isUploading else { return }
        items = []
        var queue: [(source: BatchSource, itemID: UUID)] = []
        for pickerItem in pickerItems {
            let kind = Self.isVideo(pickerItem) ? "動画" : "写真"
            let item = UploadItem(displayName: "\(kind) \(items.count + 1)")
            items.append(item)
            queue.append((.picker(pickerItem), item.id))
        }
        await runBatch(queue)
    }

    /// One-tap differential backup: uploads every photo/video in the library
    /// that has not been backed up yet, preserving album names in S3.
    /// `beforeStart` runs only when there is something to upload (used to
    /// gate on the rewarded ad without showing it for empty scans).
    func backupNewItems(beforeStart: () async -> Void = {}) async {
        guard !isUploading else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            infoMessage = "写真ライブラリへのアクセスが許可されていません。設定 > プライバシーとセキュリティ > 写真 から許可してください"
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        var newAssets: [PHAsset] = []
        allAssets.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image || asset.mediaType == .video else { return }
            if !UploadedAssetsStore.contains(asset.localIdentifier) {
                newAssets.append(asset)
            }
        }

        guard !newAssets.isEmpty else {
            infoMessage = "新しい写真・動画はありません(すべてバックアップ済みです)"
            return
        }

        await beforeStart()
        await handleAssets(newAssets)
    }

    /// Uploads specific library assets (from the in-app library picker or
    /// the differential backup), preserving album names in S3.
    func handleAssets(_ assets: [PHAsset]) async {
        guard !assets.isEmpty, !isUploading else { return }
        items = []
        var queue: [(source: BatchSource, itemID: UUID)] = []
        for asset in assets {
            let kind = asset.mediaType == .video ? "動画" : "写真"
            let item = UploadItem(displayName: "\(kind) \(items.count + 1)")
            items.append(item)
            queue.append((.asset(asset), item.id))
        }
        await runBatch(queue)
    }

    /// Uploads one photo taken with the in-app camera. Camera shots skip the
    /// rewarded ad (a per-shot ad would make the capture flow unusable) and
    /// the dedup store (they are not library assets).
    func handleCapturedImage(_ image: UIImage) async {
        guard !isUploading else { return }
        items = []
        let item = UploadItem(displayName: "撮影した写真")
        items.append(item)
        await runBatch([(.captured(image), item.id)])
    }

    private enum BatchSource {
        case picker(PhotosPickerItem)
        case asset(PHAsset)
        case captured(UIImage)
    }

    private func runBatch(_ queue: [(source: BatchSource, itemID: UUID)]) async {
        isUploading = true
        let startedAt = Date()
        persistItems()

        // Keep the screen awake while the batch runs so the user can watch
        // progress; transfers themselves survive lock/background regardless.
        UIApplication.shared.isIdleTimerDisabled = true

        // Ask iOS for extra runtime if the user backgrounds the app while
        // photos are still being read from the library.
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "prepare-uploads") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }

        defer {
            isUploading = false
            UIApplication.shared.isIdleTimerDisabled = false
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            UploadHistoryStore.append(
                UploadBatchSummary(
                    id: UUID(),
                    date: startedAt,
                    total: items.count,
                    done: doneCount,
                    skipped: skippedCount,
                    failed: failedCount
                )
            )
            history = UploadHistoryStore.load()
            persistItems()
        }

        await withTaskGroup(of: Void.self) { group in
            var iterator = queue.makeIterator()
            for _ in 0..<maxConcurrentUploads {
                guard let next = iterator.next() else { break }
                group.addTask { await self.upload(next.source, itemID: next.itemID) }
            }
            while await group.next() != nil {
                guard let next = iterator.next() else { continue }
                group.addTask { await self.upload(next.source, itemID: next.itemID) }
            }
        }
    }

    private func upload(_ source: BatchSource, itemID: UUID) async {
        switch source {
        case .picker(let pickerItem):
            await upload(pickerItem, itemID: itemID)
        case .asset(let asset):
            await upload(asset, itemID: itemID)
        case .captured(let image):
            await upload(capturedImage: image, itemID: itemID)
        }
    }

    private func upload(capturedImage image: UIImage, itemID: UUID) async {
        do {
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                update(itemID) { $0.status = .failed(message: "撮影した写真を変換できませんでした") }
                return
            }
            let thumbnail = await Self.makeThumbnail(from: data)
            update(itemID) { $0.thumbnail = thumbnail }
            let fileURL = try await Self.writeTemporaryFile(data: data)
            try await startBackgroundUpload(
                fileURL: fileURL,
                contentType: "image/jpeg",
                album: nil,
                itemID: itemID
            )
        } catch {
            update(itemID) { $0.status = .failed(message: error.localizedDescription) }
        }
    }

    func clearHistory() {
        UploadHistoryStore.clear()
        history = []
    }

    private func upload(_ pickerItem: PhotosPickerItem, itemID: UUID) async {
        // Items already uploaded in a previous batch are skipped, not resent.
        if let assetID = pickerItem.itemIdentifier, UploadedAssetsStore.contains(assetID) {
            update(itemID) { $0.status = .skipped }
            return
        }

        if Self.isVideo(pickerItem) {
            await uploadVideo(pickerItem, itemID: itemID)
            return
        }

        do {
            guard let rawData = try await pickerItem.loadTransferable(type: Data.self) else {
                update(itemID) { $0.status = .failed(message: "写真を読み込めませんでした") }
                return
            }

            let rawContentType = pickerItem.supportedContentTypes
                .compactMap(\.preferredMIMEType)
                .first ?? "image/jpeg"

            let thumbnail = await Self.makeThumbnail(from: rawData)
            update(itemID) { $0.thumbnail = thumbnail }

            guard let (data, contentType) = await Self.prepareForUpload(
                data: rawData,
                contentType: rawContentType
            ) else {
                update(itemID) { $0.status = .failed(message: "対応していない画像形式です") }
                return
            }

            // Background sessions upload from files, not memory.
            let fileURL = try await Self.writeTemporaryFile(data: data)

            update(itemID) { $0.status = .uploading(progress: 0) }

            let key = try await BackgroundUploadManager.shared.upload(
                fileURL: fileURL,
                contentType: contentType,
                storageClass: StorageModeStore.current.rawValue
            ) { progress in
                Task { @MainActor [weak self] in
                    self?.update(itemID) { $0.status = .uploading(progress: progress) }
                }
            }

            update(itemID) { $0.status = .done(key: key) }
            if let assetID = pickerItem.itemIdentifier {
                UploadedAssetsStore.insert(assetID)
            }
        } catch {
            update(itemID) { $0.status = .failed(message: error.localizedDescription) }
        }
    }

    /// Videos are staged as files (never loaded into memory whole) and are
    /// uploaded as-is — no re-encode fallback like images have.
    private func uploadVideo(_ pickerItem: PhotosPickerItem, itemID: UUID) async {
        do {
            guard let movie = try await pickerItem.loadTransferable(type: PickedMovie.self) else {
                update(itemID) { $0.status = .failed(message: "動画を読み込めませんでした") }
                return
            }

            let contentType = pickerItem.supportedContentTypes
                .first { $0.conforms(to: .movie) }?
                .preferredMIMEType ?? "video/quicktime"
            guard Self.supportedVideoMimeTypes.contains(contentType) else {
                update(itemID) { $0.status = .failed(message: "対応していない動画形式です") }
                return
            }

            let thumbnail = await Self.makeVideoThumbnail(for: movie.url)
            update(itemID) { $0.thumbnail = thumbnail }
            update(itemID) { $0.status = .uploading(progress: 0) }

            let key = try await BackgroundUploadManager.shared.upload(
                fileURL: movie.url,
                contentType: contentType,
                storageClass: StorageModeStore.current.rawValue
            ) { progress in
                Task { @MainActor [weak self] in
                    self?.update(itemID) { $0.status = .uploading(progress: progress) }
                }
            }

            update(itemID) { $0.status = .done(key: key) }
            if let assetID = pickerItem.itemIdentifier {
                UploadedAssetsStore.insert(assetID)
            }
        } catch {
            update(itemID) { $0.status = .failed(message: error.localizedDescription) }
        }
    }

    nonisolated private static func isVideo(_ pickerItem: PhotosPickerItem) -> Bool {
        pickerItem.supportedContentTypes.contains { $0.conforms(to: .movie) }
    }

    /// Differential-backup path: uploads one PHAsset, tagging it with the
    /// name of the (first) album it belongs to so S3 mirrors the structure.
    private func upload(_ asset: PHAsset, itemID: UUID) async {
        do {
            let album = Self.albumName(for: asset)

            if asset.mediaType == .video {
                let (fileURL, contentType) = try await Self.exportVideo(asset)
                guard Self.supportedVideoMimeTypes.contains(contentType) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    update(itemID) { $0.status = .failed(message: "対応していない動画形式です") }
                    return
                }
                let thumbnail = await Self.makeVideoThumbnail(for: fileURL)
                update(itemID) { $0.thumbnail = thumbnail }
                try await startBackgroundUpload(
                    fileURL: fileURL,
                    contentType: contentType,
                    album: album,
                    itemID: itemID
                )
            } else {
                let (rawData, rawContentType) = try await Self.exportImageData(asset)
                let thumbnail = await Self.makeThumbnail(from: rawData)
                update(itemID) { $0.thumbnail = thumbnail }
                guard let (data, contentType) = await Self.prepareForUpload(
                    data: rawData,
                    contentType: rawContentType
                ) else {
                    update(itemID) { $0.status = .failed(message: "対応していない画像形式です") }
                    return
                }
                let fileURL = try await Self.writeTemporaryFile(data: data)
                try await startBackgroundUpload(
                    fileURL: fileURL,
                    contentType: contentType,
                    album: album,
                    itemID: itemID
                )
            }

            UploadedAssetsStore.insert(asset.localIdentifier)
        } catch {
            update(itemID) { $0.status = .failed(message: error.localizedDescription) }
        }
    }

    /// Shared tail of both upload paths: hand the staged file to the
    /// background session and reflect progress/result in the list.
    private func startBackgroundUpload(
        fileURL: URL,
        contentType: String,
        album: String?,
        itemID: UUID
    ) async throws {
        update(itemID) { $0.status = .uploading(progress: 0) }
        let key = try await BackgroundUploadManager.shared.upload(
            fileURL: fileURL,
            contentType: contentType,
            storageClass: StorageModeStore.current.rawValue,
            album: album
        ) { progress in
            Task { @MainActor [weak self] in
                self?.update(itemID) { $0.status = .uploading(progress: progress) }
            }
        }
        update(itemID) { $0.status = .done(key: key) }
    }

    /// The name of the first user album containing the asset, if any.
    nonisolated private static func albumName(for asset: PHAsset) -> String? {
        let collections = PHAssetCollection.fetchAssetCollectionsContaining(
            asset,
            with: .album,
            options: nil
        )
        return collections.firstObject?.localizedTitle
    }

    /// Original image bytes + MIME type for a library asset. Allows network
    /// access so iCloud-offloaded originals are fetched too.
    nonisolated private static func exportImageData(
        _ asset: PHAsset
    ) async throws -> (Data, String) {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, uti, _, _ in
                guard let data else {
                    continuation.resume(
                        throwing: AssetExportError(message: "写真を読み込めませんでした")
                    )
                    return
                }
                let mime = uti.flatMap { UTType($0)?.preferredMIMEType } ?? "image/jpeg"
                continuation.resume(returning: (data, mime))
            }
        }
    }

    /// Stages a library video as a temp file and returns its MIME type.
    nonisolated private static func exportVideo(
        _ asset: PHAsset
    ) async throws -> (URL, String) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .video })
            ?? resources.first(where: { $0.type == .fullSizeVideo })
        else {
            throw AssetExportError(message: "動画を読み込めませんでした")
        }

        let type = UTType(resource.uniformTypeIdentifier)
        let ext = type?.preferredFilenameExtension ?? "mov"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-uploads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(
            for: resource,
            toFile: destination,
            options: options
        )
        return (destination, type?.preferredMIMEType ?? "video/quicktime")
    }

    private func update(_ id: UUID, _ mutate: (inout UploadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let kindBefore = items[index].persisted.kind
        mutate(&items[index])
        // Persist on state transitions only — not on every progress tick.
        if items[index].persisted.kind != kindBefore {
            persistItems()
        }
    }

    private func persistItems() {
        UploadItemsSnapshotStore.save(items.map(\.persisted))
    }

    /// Runs off the main actor: image decode / re-encode can be slow for large photos.
    nonisolated private static func prepareForUpload(
        data: Data,
        contentType: String
    ) async -> (data: Data, contentType: String)? {
        if supportedMimeTypes.contains(contentType) {
            return (data, contentType)
        }
        guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        return (jpeg, "image/jpeg")
    }

    /// Runs off the main actor: thumbnail generation decodes the full image.
    nonisolated private static func makeThumbnail(from data: Data) async -> UIImage? {
        UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 120, height: 120))
    }

    /// Grabs the first frame of a staged video file for the list thumbnail.
    nonisolated private static func makeVideoThumbnail(for url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let cgImage = try? await generator.image(at: .zero).image else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Runs off the main actor: stages the photo bytes for the background session.
    nonisolated private static func writeTemporaryFile(data: Data) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-uploads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(UUID().uuidString)
        try data.write(to: fileURL)
        return fileURL
    }
}

/// Failure while reading an asset out of the photo library.
private struct AssetExportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Receives a picked video as a staged file copy. Videos can be hundreds of
/// megabytes, so they must never be loaded into memory the way photos are.
private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("pending-uploads", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}
