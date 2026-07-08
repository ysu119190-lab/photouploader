import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class UploadViewModel: ObservableObject {
    @Published private(set) var items: [UploadItem] = []
    @Published private(set) var isUploading = false

    var doneCount: Int {
        items.filter { if case .done = $0.status { return true } else { return false } }.count
    }

    var failedCount: Int {
        items.filter { if case .failed = $0.status { return true } else { return false } }.count
    }

    /// How many photos are prepared and uploaded at the same time. Raising
    /// this speeds up large batches but increases memory and network pressure.
    private let maxConcurrentUploads = 4

    /// MIME types the backend accepts as-is; anything else is re-encoded to JPEG.
    private static let supportedMimeTypes: Set<String> = [
        "image/jpeg", "image/png", "image/heic", "image/heif", "image/webp", "image/gif",
    ]

    /// Uploads the picked photos, at most `maxConcurrentUploads` at a time.
    /// Once a photo is handed to the background session, its transfer survives
    /// backgrounding; this method only needs the app alive while photos are
    /// being read from the photo library and prepared.
    func handleSelection(_ pickerItems: [PhotosPickerItem]) async {
        guard !pickerItems.isEmpty, !isUploading else { return }
        isUploading = true
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
        }

        var queue: [(pickerItem: PhotosPickerItem, itemID: UUID)] = []
        for pickerItem in pickerItems {
            let item = UploadItem(displayName: "写真 \(items.count + 1)")
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

    func clearFinished() {
        items.removeAll { item in
            if case .done = item.status { return true }
            return false
        }
    }

    private func upload(_ pickerItem: PhotosPickerItem, itemID: UUID) async {
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
                contentType: contentType
            ) { progress in
                Task { @MainActor [weak self] in
                    self?.update(itemID) { $0.status = .uploading(progress: progress) }
                }
            }

            update(itemID) { $0.status = .done(key: key) }
        } catch {
            update(itemID) { $0.status = .failed(message: error.localizedDescription) }
        }
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
