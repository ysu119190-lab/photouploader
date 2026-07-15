import Foundation

struct PresignResponse: Decodable {
    let uploadUrl: String
    let key: String
    let expiresIn: Int
    /// The S3 storage class the URL was signed for. When not "STANDARD", the
    /// PUT must carry a matching x-amz-storage-class header.
    let storageClass: String?
    /// Piggybacked PUT URL for the JPEG thumbnail (when requested).
    let thumbnailUploadUrl: String?
    let thumbnailKey: String?
}

/// Response of the thumbnail-only re-sign (`thumbnailFor` request).
struct ThumbnailPresignResponse: Decodable {
    let thumbnailUploadUrl: String
    let thumbnailKey: String
}

enum UploadError: LocalizedError {
    case presignFailed(status: Int)
    case invalidUploadURL
    case uploadFailed(status: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .presignFailed(let status):
            return "アップロードURLの取得に失敗しました (HTTP \(status))"
        case .invalidUploadURL:
            return "サーバーから不正なURLが返されました"
        case .uploadFailed(let status, let detail):
            if let detail, !detail.isEmpty {
                return "S3へのアップロードに失敗しました (HTTP \(status) / \(detail))"
            }
            return "S3へのアップロードに失敗しました (HTTP \(status))"
        }
    }
}

/// Requests presigned S3 PUT URLs from the backend, authenticating with the
/// signed-in user's Cognito ID token (auto-refreshed by TokenProvider).
enum PresignClient {
    static func requestPresignedURL(
        contentType: String,
        storageClass: String,
        album: String? = nil,
        wantsThumbnail: Bool = false
    ) async throws -> PresignResponse {
        var body: [String: Any] = [
            "contentType": contentType,
            "storageClass": storageClass,
        ]
        if let album, !album.isEmpty {
            // The backend mirrors the album as a folder in the object key.
            body["album"] = album
        }
        if wantsThumbnail {
            // One request returns both PUT URLs — no extra API call for thumbs.
            body["thumbnail"] = true
        }
        return try await post(body: body)
    }

    /// Re-signs just the thumbnail PUT for an already-uploaded key, used when
    /// the piggybacked URL expired while the main transfer sat in the queue.
    static func requestThumbnailURL(for key: String) async throws -> ThumbnailPresignResponse {
        try await post(body: ["thumbnailFor": key])
    }

    private static func post<Response: Decodable>(body: [String: Any]) async throws -> Response {
        let config = try BackendConfigStore.required()
        let idToken = try await TokenProvider.shared.validIdToken()

        var request = URLRequest(url: config.apiBaseURL.appendingPathComponent("presign"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UploadError.presignFailed(status: status)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
