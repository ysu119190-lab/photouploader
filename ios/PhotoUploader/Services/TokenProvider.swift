import Foundation

/// Owns the signed-in user's tokens: persists them in the Keychain and hands
/// out a valid (auto-refreshed) ID token to API callers. UI-independent, so
/// background upload retries can use it too.
actor TokenProvider {
    static let shared = TokenProvider()

    private static let keychainKey = "auth-tokens"

    private struct StoredTokens: Codable {
        var idToken: String
        // Optional so payloads persisted by app versions that only stored the
        // ID token still decode; a refresh fills it in when first needed.
        var accessToken: String?
        var refreshToken: String
        var expiresAt: Date
    }

    private var cache: StoredTokens?

    func isSignedIn() -> Bool {
        loadTokens() != nil
    }

    func store(_ tokens: AuthTokens) {
        persist(
            StoredTokens(
                idToken: tokens.idToken,
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
            )
        )
    }

    func signOut() {
        cache = nil
        KeychainStore.delete(Self.keychainKey)
    }

    /// Returns a non-expired ID token, refreshing it with the stored refresh
    /// token when needed. Throws `AuthError.notSignedIn` when there is no
    /// session or the refresh token itself has expired.
    func validIdToken() async throws -> String {
        try await validTokens().idToken
    }

    /// Returns a non-expired access token (for user-self-service calls like
    /// account deletion), refreshing when needed.
    func validAccessToken() async throws -> String {
        let tokens = try await validTokens()
        if let accessToken = tokens.accessToken {
            return accessToken
        }
        // Pre-access-token payload that is still fresh — refresh to get one.
        guard let accessToken = try await refreshTokens(with: tokens.refreshToken).accessToken else {
            throw AuthError.unexpectedResponse
        }
        return accessToken
    }

    private func validTokens() async throws -> StoredTokens {
        guard let tokens = loadTokens() else {
            throw AuthError.notSignedIn
        }
        if tokens.expiresAt.timeIntervalSinceNow > 60 {
            return tokens
        }
        return try await refreshTokens(with: tokens.refreshToken)
    }

    private func refreshTokens(with refreshToken: String) async throws -> StoredTokens {
        do {
            let refreshed = try await CognitoAuthClient.refresh(refreshToken: refreshToken)
            store(refreshed)
            guard let stored = loadTokens() else {
                throw AuthError.notSignedIn
            }
            return stored
        } catch let error as CognitoError where error.type == "NotAuthorizedException" {
            // Refresh token expired or revoked — the user must sign in again.
            signOut()
            throw AuthError.notSignedIn
        }
    }

    private func loadTokens() -> StoredTokens? {
        if let cache {
            return cache
        }
        guard let data = KeychainStore.load(Self.keychainKey),
              let stored = try? JSONDecoder().decode(StoredTokens.self, from: data)
        else {
            return nil
        }
        cache = stored
        return stored
    }

    private func persist(_ tokens: StoredTokens) {
        cache = tokens
        if let data = try? JSONEncoder().encode(tokens) {
            KeychainStore.save(data, for: Self.keychainKey)
        }
    }
}
