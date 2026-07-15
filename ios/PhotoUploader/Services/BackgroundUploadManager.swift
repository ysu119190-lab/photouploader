import Foundation

/// Uploads photo files to S3 through a background `URLSession`, so transfers
/// keep running when the app is backgrounded, the screen locks, or the app is
/// terminated by the system.
///
/// Each upload is a file-based task tagged (via `taskDescription`) with JSON
/// metadata, so the manager can resolve results — and retry with a fresh
/// presigned URL — even for tasks that finish after an app relaunch.
/// What an upload resolves to: the S3 key, plus (when a thumbnail was
/// requested) the presigned PUT URL for it, signed together with the final
/// attempt's main URL.
struct BackgroundUploadResult {
    let key: String
    let thumbnailUploadURL: String?
}

final class BackgroundUploadManager: NSObject {
    static let shared = BackgroundUploadManager()
    static let sessionIdentifier = "com.example.PhotoUploader.upload"

    /// Set by the app delegate when iOS relaunches the app for session events;
    /// called once all pending delegate messages have been delivered.
    var backgroundCompletionHandler: (() -> Void)?

    private var session: URLSession!
    private let lock = NSLock()
    private var continuations: [String: CheckedContinuation<BackgroundUploadResult, Error>] = [:]
    private var progressHandlers: [String: @Sendable (Double) -> Void] = [:]
    /// Response bodies keyed by task identifier, so S3's XML error detail can
    /// be surfaced when an upload is rejected.
    private var responseBodies: [Int: Data] = [:]

    private static let maxAttempts = 3

    private struct TaskMetadata: Codable {
        let uploadID: String
        let filePath: String
        let contentType: String
        let storageClass: String
        // Optionals so task descriptions written by older app versions still
        // decode after an update mid-transfer.
        let album: String?
        let wantsThumbnail: Bool?
        let thumbnailUploadUrl: String?
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
        storageClass: String,
        album: String? = nil,
        wantsThumbnail: Bool = false,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> BackgroundUploadResult {
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
                        storageClass: storageClass,
                        album: album,
                        wantsThumbnail: wantsThumbnail,
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
        storageClass: String,
        album: String?,
        wantsThumbnail: Bool,
        attempt: Int
    ) async throws {
        let presign = try await PresignClient.requestPresignedURL(
            contentType: contentType,
            storageClass: storageClass,
            album: album,
            wantsThumbnail: wantsThumbnail
        )
        guard let uploadURL = URL(string: presign.uploadUrl) else {
            throw UploadError.invalidUploadURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        // Must match the contentType the URL was signed for.
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // For non-STANDARD classes the URL is signed with the storage class,
        // so the PUT must echo it in this header or S3 returns 403.
        if let signedClass = presign.storageClass, signedClass != "STANDARD" {
            request.setValue(signedClass, forHTTPHeaderField: "x-amz-storage-class")
        }

        let metadata = TaskMetadata(
            uploadID: uploadID,
            filePath: fileURL.path,
            contentType: contentType,
            storageClass: storageClass,
            album: album,
            wantsThumbnail: wantsThumbnail,
            thumbnailUploadUrl: presign.thumbnailUploadUrl,
            key: presign.key,
            attempt: attempt
        )
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = String(data: try JSONEncoder().encode(metadata), encoding: .utf8)
        task.resume()
    }

    private func finish(_ uploadID: String, with result: Result<BackgroundUploadResult, Error>) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: uploadID)
        progressHandlers.removeValue(forKey: uploadID)
        lock.unlock()

        switch result {
        case .success(let uploadResult):
            continuation?.resume(returning: uploadResult)
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

    private func takeResponseBody(for task: URLSessionTask) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return responseBodies.removeValue(forKey: task.taskIdentifier)
    }

    /// Pulls <Code> and <Message> out of an S3 error XML body, e.g.
    /// "SignatureDoesNotMatch: The request signature we calculated...".
    private static func errorDetail(from body: Data?) -> String? {
        guard let body, let xml = String(data: body, encoding: .utf8) else { return nil }
        func tag(_ name: String) -> String? {
            guard let start = xml.range(of: "<\(name)>"),
                  let end = xml.range(of: "</\(name)>"),
                  start.upperBound <= end.lowerBound
            else { return nil }
            return String(xml[start.upperBound..<end.lowerBound])
        }
        guard let code = tag("Code") else { return nil }
        if let message = tag("Message") {
            return "\(code): \(message)"
        }
        return code
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
        let responseBody = takeResponseBody(for: task)

        if let error {
            deleteFile(at: fileURL)
            finish(metadata.uploadID, with: .failure(error))
            return
        }

        let status = (task.response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200:
            deleteFile(at: fileURL)
            finish(
                metadata.uploadID,
                with: .success(
                    BackgroundUploadResult(
                        key: metadata.key,
                        thumbnailUploadURL: metadata.thumbnailUploadUrl
                    )
                )
            )
        case 403 where metadata.attempt < Self.maxAttempts:
            // The presigned URL likely expired while the task waited in the
            // background queue — sign a fresh one and try again.
            Task {
                do {
                    try await self.enqueueTask(
                        uploadID: metadata.uploadID,
                        fileURL: fileURL,
                        contentType: metadata.contentType,
                        storageClass: metadata.storageClass,
                        album: metadata.album,
                        wantsThumbnail: metadata.wantsThumbnail ?? false,
                        attempt: metadata.attempt + 1
                    )
                } catch {
                    self.deleteFile(at: fileURL)
                    self.finish(metadata.uploadID, with: .failure(error))
                }
            }
        default:
            deleteFile(at: fileURL)
            finish(
                metadata.uploadID,
                with: .failure(
                    UploadError.uploadFailed(
                        status: status,
                        detail: Self.errorDetail(from: responseBody)
                    )
                )
            )
        }
    }
}

extension BackgroundUploadManager: URLSessionDataDelegate {
    // Upload tasks deliver their (small) response bodies here; keep them so
    // rejected uploads can show S3's error code instead of just the status.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        responseBodies[dataTask.taskIdentifier, default: Data()].append(data)
        lock.unlock()
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
