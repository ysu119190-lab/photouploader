import Foundation

/// Uploads photo files to S3 through a background `URLSession`, so transfers
/// keep running when the app is backgrounded, the screen locks, or the app is
/// terminated by the system.
///
/// Each upload is a file-based task tagged (via `taskDescription`) with JSON
/// metadata, so the manager can resolve results — and retry with a fresh
/// presigned URL — even for tasks that finish after an app relaunch.
final class BackgroundUploadManager: NSObject {
    static let shared = BackgroundUploadManager()
    static let sessionIdentifier = "com.example.PhotoUploader.upload"

    /// Set by the app delegate when iOS relaunches the app for session events;
    /// called once all pending delegate messages have been delivered.
    var backgroundCompletionHandler: (() -> Void)?

    private var session: URLSession!
    private let lock = NSLock()
    private var continuations: [String: CheckedContinuation<String, Error>] = [:]
    private var progressHandlers: [String: @Sendable (Double) -> Void] = [:]

    private static let maxAttempts = 3

    private struct TaskMetadata: Codable {
        let uploadID: String
        let filePath: String
        let contentType: String
        let key: String
        let attempt: Int
    }

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Uploads the file at `fileURL` and returns the S3 object key.
    /// The file is deleted once the upload finishes (success or terminal failure).
    func upload(
        fileURL: URL,
        contentType: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        let uploadID = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations[uploadID] = continuation
            progressHandlers[uploadID] = onProgress
            lock.unlock()

            Task {
                do {
                    try await self.enqueueTask(
                        uploadID: uploadID,
                        fileURL: fileURL,
                        contentType: contentType,
                        attempt: 1
                    )
                } catch {
                    self.deleteFile(at: fileURL)
                    self.finish(uploadID, with: .failure(error))
                }
            }
        }
    }

    /// Requests a presigned URL and hands the file to the background session.
    private func enqueueTask(
        uploadID: String,
        fileURL: URL,
        contentType: String,
        attempt: Int
    ) async throws {
        let presign = try await PresignClient.requestPresignedURL(contentType: contentType)
        guard let uploadURL = URL(string: presign.uploadUrl) else {
            throw UploadError.invalidUploadURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        // Must match the contentType the URL was signed for.
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let metadata = TaskMetadata(
            uploadID: uploadID,
            filePath: fileURL.path,
            contentType: contentType,
            key: presign.key,
            attempt: attempt
        )
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = String(data: try JSONEncoder().encode(metadata), encoding: .utf8)
        task.resume()
    }

    private func finish(_ uploadID: String, with result: Result<String, Error>) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: uploadID)
        progressHandlers.removeValue(forKey: uploadID)
        lock.unlock()

        switch result {
        case .success(let key):
            continuation?.resume(returning: key)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func metadata(for task: URLSessionTask) -> TaskMetadata? {
        guard let description = task.taskDescription,
              let data = description.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TaskMetadata.self, from: data)
    }

    private func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

extension BackgroundUploadManager: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0, let metadata = metadata(for: task) else { return }
        lock.lock()
        let handler = progressHandlers[metadata.uploadID]
        lock.unlock()
        handler?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let metadata = metadata(for: task) else { return }
        let fileURL = URL(fileURLWithPath: metadata.filePath)

        if let error {
            deleteFile(at: fileURL)
            finish(metadata.uploadID, with: .failure(error))
            return
        }

        let status = (task.response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200:
            deleteFile(at: fileURL)
            finish(metadata.uploadID, with: .success(metadata.key))
        case 403 where metadata.attempt < Self.maxAttempts:
            // The presigned URL likely expired while the task waited in the
            // background queue — sign a fresh one and try again.
            Task {
                do {
                    try await self.enqueueTask(
                        uploadID: metadata.uploadID,
                        fileURL: fileURL,
                        contentType: metadata.contentType,
                        attempt: metadata.attempt + 1
                    )
                } catch {
                    self.deleteFile(at: fileURL)
                    self.finish(metadata.uploadID, with: .failure(error))
                }
            }
        default:
            deleteFile(at: fileURL)
            finish(metadata.uploadID, with: .failure(UploadError.uploadFailed(status: status)))
        }
    }
}

extension BackgroundUploadManager: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
