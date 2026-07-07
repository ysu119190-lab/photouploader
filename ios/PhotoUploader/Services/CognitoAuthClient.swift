import Foundation

struct AuthTokens {
    let idToken: String
    let refreshToken: String
    let expiresIn: Int
}

enum AuthError: LocalizedError {
    case notSignedIn
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "ログインが必要です"
        case .unexpectedResponse:
            return "サーバーから想定外の応答が返されました"
        }
    }
}

/// A Cognito API error, mapped to a user-facing Japanese message.
struct CognitoError: LocalizedError {
    let type: String
    let rawMessage: String

    var errorDescription: String? {
        switch type {
        case "NotAuthorizedException":
            return "メールアドレスまたはパスワードが正しくありません"
        case "UserNotFoundException":
            return "このメールアドレスは登録されていません"
        case "UsernameExistsException":
            return "このメールアドレスはすでに登録されています"
        case "InvalidPasswordException", "InvalidParameterException":
            return "入力内容が要件を満たしていません(パスワードは8文字以上)"
        case "CodeMismatchException":
            return "確認コードが正しくありません"
        case "ExpiredCodeException":
            return "確認コードの有効期限が切れています"
        case "UserNotConfirmedException":
            return "メールアドレスの確認が完了していません"
        case "LimitExceededException", "TooManyRequestsException":
            return "試行回数が多すぎます。しばらく待ってからお試しください"
        default:
            return rawMessage.isEmpty ? "認証エラーが発生しました (\(type))" : rawMessage
        }
    }
}

/// Talks to the Cognito user pool API (sign-up / sign-in / token refresh).
/// These are public, unauthenticated Cognito operations — no AWS credentials
/// or SDK needed, just the app client ID.
enum CognitoAuthClient {
    private static var endpointURL: URL {
        URL(string: "https://cognito-idp.\(AppConfig.cognitoRegion).amazonaws.com/")!
    }

    static func signUp(email: String, password: String) async throws {
        _ = try await call(
            target: "SignUp",
            payload: [
                "ClientId": AppConfig.cognitoClientId,
                "Username": email,
                "Password": password,
                "UserAttributes": [["Name": "email", "Value": email]],
            ]
        )
    }

    static func confirmSignUp(email: String, code: String) async throws {
        _ = try await call(
            target: "ConfirmSignUp",
            payload: [
                "ClientId": AppConfig.cognitoClientId,
                "Username": email,
                "ConfirmationCode": code,
            ]
        )
    }

    static func signIn(email: String, password: String) async throws -> AuthTokens {
        let result = try await call(
            target: "InitiateAuth",
            payload: [
                "AuthFlow": "USER_PASSWORD_AUTH",
                "ClientId": AppConfig.cognitoClientId,
                "AuthParameters": ["USERNAME": email, "PASSWORD": password],
            ]
        )
        return try parseTokens(from: result, existingRefreshToken: nil)
    }

    static func refresh(refreshToken: String) async throws -> AuthTokens {
        let result = try await call(
            target: "InitiateAuth",
            payload: [
                "AuthFlow": "REFRESH_TOKEN_AUTH",
                "ClientId": AppConfig.cognitoClientId,
                "AuthParameters": ["REFRESH_TOKEN": refreshToken],
            ]
        )
        // Refresh responses don't include a new refresh token; keep the old one.
        return try parseTokens(from: result, existingRefreshToken: refreshToken)
    }

    private static func parseTokens(
        from result: [String: Any],
        existingRefreshToken: String?
    ) throws -> AuthTokens {
        guard let auth = result["AuthenticationResult"] as? [String: Any],
              let idToken = auth["IdToken"] as? String,
              let expiresIn = auth["ExpiresIn"] as? Int,
              let refreshToken = (auth["RefreshToken"] as? String) ?? existingRefreshToken
        else {
            throw AuthError.unexpectedResponse
        }
        return AuthTokens(idToken: idToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }

    private static func call(target: String, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "AWSCognitoIdentityProviderService.\(target)",
            forHTTPHeaderField: "X-Amz-Target"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.unexpectedResponse
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard http.statusCode == 200 else {
            // __type looks like "com.amazonaws.cognito...#NotAuthorizedException"
            // or just "NotAuthorizedException" depending on the error.
            let rawType = (json["__type"] as? String) ?? "UnknownError"
            let type = rawType.components(separatedBy: "#").last ?? rawType
            let message = (json["message"] as? String) ?? (json["Message"] as? String) ?? ""
            throw CognitoError(type: type, rawMessage: message)
        }
        return json
    }
}
