import Foundation

/// Backend connection settings.
///
/// After deploying the backend (`sam deploy`), replace the values below with
/// the CloudFormation stack outputs. None of these are secrets — the API is
/// protected by Cognito sign-in, and the client ID is a public identifier —
/// so committing them to a private repository is fine.
enum AppConfig {
    /// Stack output `ApiEndpoint`.
    static let apiBaseURL = URL(string: "https://REPLACE_ME.execute-api.ap-northeast-1.amazonaws.com")!

    /// Stack output `Region` (e.g. "ap-northeast-1").
    static let cognitoRegion = "ap-northeast-1"

    /// Stack output `UserPoolClientId`.
    static let cognitoClientId = "REPLACE_ME"
}
