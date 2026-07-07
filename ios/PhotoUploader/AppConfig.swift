import Foundation

/// Backend connection settings.
///
/// After deploying the backend (`sam deploy`), replace the two values below:
/// - `apiBaseURL`: the `ApiEndpoint` output of the CloudFormation stack
/// - `apiKey`: the value you passed as the `ApiKey` stack parameter
enum AppConfig {
    static let apiBaseURL = URL(string: "https://REPLACE_ME.execute-api.ap-northeast-1.amazonaws.com")!
    static let apiKey = "REPLACE_ME"
}
