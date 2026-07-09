import Foundation

/// One uploaded photo as returned by GET /photos.
struct RemotePhoto: Decodable, Identifiable {
    let key: String
    let size: Int
    let lastModified: String
    /// Presigned GET URL, valid for about an hour.
    let url: String

    var id: String { key }

    var imageURL: URL? { URL(string: url) }

    var uploadedAt: Date? {
        ISO8601DateFormatter().date(from: lastModified)
    }
}

struct PhotoListResponse: Decodable {
    let photos: [RemotePhoto]
    let total: Int
    let nextOffset: Int?
}

enum GalleryError: LocalizedError {
    case requestFailed(status: Int)
    case unexpectedResponse(status: Int, bodyPrefix: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status):
            return "写真一覧の取得に失敗しました (HTTP \(status))"
        case .unexpectedResponse(let status, let bodyPrefix):
            return "サーバー応答を解釈できませんでした (HTTP \(status)): \(bodyPrefix)"
        }
    }
}

/// Fetches the caller's uploaded photos from the backend.
enum GalleryClient {
    static func fetchPhotos(offset: Int, limit: Int = 40) async throws -> PhotoListResponse {
        let config = try BackendConfigStore.required()
        let idToken = try await TokenProvider.shared.validIdToken()

        var components = URLComponents(
            url: config.apiBaseURL.appendingPathComponent("photos"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else {
            throw GalleryError.requestFailed(status: -1)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GalleryError.requestFailed(status: status)
        }
        do {
            return try JSONDecoder().decode(PhotoListResponse.self, from: data)
        } catch {
            // Surface what the server actually sent so mismatches are
            // diagnosable from the device.
            let body = String(data: data.prefix(160), encoding: .utf8) ?? "(non-UTF8)"
            throw GalleryError.unexpectedResponse(status: http.statusCode, bodyPrefix: body)
        }
    }
}
