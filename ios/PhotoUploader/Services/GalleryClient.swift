import Foundation

/// One uploaded photo as returned by GET /photos.
struct RemotePhoto: Decodable, Identifiable {
    let key: String
    let size: Int
    let lastModified: String
    /// Presigned GET URL, valid for about an hour.
    let url: String
    /// Presigned GET URL of the small JPEG thumbnail, when one exists
    /// (uploads made by older app versions have none).
    let thumbnailUrl: String?

    var id: String { key }

    var imageURL: URL? { URL(string: url) }

    var thumbnailURL: URL? { thumbnailUrl.flatMap(URL.init(string:)) }

    /// What the grid should load: the cheap thumbnail when available,
    /// otherwise the full object.
    var gridImageURL: URL? { thumbnailURL ?? imageURL }

    /// The key's extension is assigned by the backend per content type, so it
    /// reliably distinguishes videos from photos.
    var isVideo: Bool {
        let ext = (key as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext)
    }

    /// Album folder embedded in the key (uploads/<sub>/albums/<name>/...).
    var albumName: String? {
        let parts = key.split(separator: "/")
        guard parts.count > 3, parts[0] == "uploads", parts[2] == "albums" else {
            return nil
        }
        return String(parts[3])
    }

    var uploadedAt: Date? {
        ISO8601DateFormatter().date(from: lastModified)
    }
}

struct PhotoListResponse: Decodable {
    let photos: [RemotePhoto]
    let total: Int
    let nextOffset: Int?
    /// Every album name that exists in the user's uploads (unfiltered).
    let albums: [String]?
}

struct PhotoDeleteResponse: Decodable {
    let deleted: [String]
    struct DeleteError: Decodable {
        let key: String
        let error: String
    }
    let errors: [DeleteError]
}

enum GalleryError: LocalizedError {
    case requestFailed(status: Int)
    case unexpectedResponse(status: Int, bodyPrefix: String)
    case deleteFailed(count: Int)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status):
            return "写真一覧の取得に失敗しました (HTTP \(status))"
        case .unexpectedResponse(let status, let bodyPrefix):
            return "サーバー応答を解釈できませんでした (HTTP \(status)): \(bodyPrefix)"
        case .deleteFailed(let count):
            return "\(count)件を削除できませんでした"
        }
    }
}

/// Fetches the caller's uploaded photos from the backend.
enum GalleryClient {
    static func fetchPhotos(
        offset: Int,
        limit: Int = 40,
        album: String? = nil
    ) async throws -> PhotoListResponse {
        let config = try BackendConfigStore.required()
        let idToken = try await TokenProvider.shared.validIdToken()

        var components = URLComponents(
            url: config.apiBaseURL.appendingPathComponent("photos"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let album {
            queryItems.append(URLQueryItem(name: "album", value: album))
        }
        components?.queryItems = queryItems
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

    /// Moves the given uploads to the server-side trash (fully deleted by a
    /// lifecycle rule after 30 days). Throws when any key failed.
    static func deletePhotos(keys: [String]) async throws {
        let config = try BackendConfigStore.required()
        let idToken = try await TokenProvider.shared.validIdToken()

        var request = URLRequest(
            url: config.apiBaseURL
                .appendingPathComponent("photos")
                .appendingPathComponent("delete")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["keys": keys])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GalleryError.requestFailed(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
        let result = try JSONDecoder().decode(PhotoDeleteResponse.self, from: data)
        if !result.errors.isEmpty {
            throw GalleryError.deleteFailed(count: result.errors.count)
        }
    }
}
