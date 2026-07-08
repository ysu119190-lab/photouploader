import Foundation

/// Connection settings for the user's own AWS backend, entered in the app's
/// setup screen (QR code / pasted JSON / manual input). None of these values
/// are secrets — the API is protected by Cognito sign-in.
struct BackendConfig: Codable, Equatable {
    var apiBaseURL: URL
    var region: String
    var clientId: String
}

enum BackendConfigStore {
    private static let defaultsKey = "backend-config"

    static func load() -> BackendConfig? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(BackendConfig.self, from: data)
    }

    static func required() throws -> BackendConfig {
        guard let config = load() else { throw AuthError.notConfigured }
        return config
    }

    static func save(_ config: BackendConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Parses the `AppConfigJson` stack output (also the QR code payload):
    /// {"apiEndpoint": "https://...", "region": "...", "clientId": "..."}
    static func parse(json text: String) -> BackendConfig? {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let endpoint = json["apiEndpoint"] as? String,
              let url = URL(string: endpoint),
              let region = json["region"] as? String,
              let clientId = json["clientId"] as? String
        else {
            return nil
        }
        return BackendConfig(apiBaseURL: url, region: region, clientId: clientId)
    }
}
