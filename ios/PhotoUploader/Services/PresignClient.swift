import Foundation

struct PresignResponse: Decodable {
    let uploadUrl: String
    let key: String
    let expiresIn: Int
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
    static func requestPresignedURL(contentType: String) async throws -> PresignResponse {
        let config = try BackendConfigStore.required()
        let idToken = try await TokenProvider.shared.validIdToken()

        var request = URLRequest(url: config.apiBaseURL.appendingPathComponent("presign"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["contentType": contentType])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UploadError.presignFailed(status: status)
        }
        return try JSONDecoder().decode(PresignResponse.self, from: data)
    }
}
