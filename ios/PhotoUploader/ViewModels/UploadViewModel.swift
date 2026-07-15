import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class UploadViewModel: ObservableObject {
    /// Photos in the current (or most recent) batch.
    @Published private(set) var items: [UploadItem] = []
    @Published private(set) var isUploading = false
    /// Finished batches, newest first, persisted across launches.
    @Published private(set) var history: [UploadBatchSummary] = UploadHistoryStore.load()

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
        isUploading = true
        items = []
        let startedAt = Date()

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
        }

        var queue: [(pickerItem: PhotosPickerItem, itemID: UUID)] = []
        for pickerItem in pickerItems {
            let kind = Self.isVideo(pickerItem) ? "動画" : "写真"
            let item = UploadItem(displayName: "\(kind) \(items.count + 1)")
            items.append(item)
            queue.append((pickerItem, item.id))
        }

        await withTaskGroup(of: Void.self) { group in
            var iterator = queue.makeIterator()
            for _ in 0..<maxConcurrentUploads {
                guard let next = iterator.next() else { break }
                group.addTask { await self.upload(next.pickerItem, itemID: next.itemID) }
            }
            while await group.next() != nil {
                guard let next = iterator.next() else { continue }
                group.addTask { await self.upload(next.pickerItem, itemID: next.itemID) }
            }
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

    private func update(_ id: UUID, _ mutate: (inout UploadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
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
