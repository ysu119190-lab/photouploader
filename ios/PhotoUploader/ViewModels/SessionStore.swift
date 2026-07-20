import SwiftUI

/// Drives the app's authentication state: signed out → (sign-up →
/// email-code confirmation →) signed in.
@MainActor
final class SessionStore: ObservableObject {
    enum State {
        case loading
        /// No backend configured yet — show the setup screen first.
        case needsSetup
        case signedOut
        /// Waiting for the email confirmation code. The password is kept so
        /// the app can sign in automatically right after confirmation.
        case needsConfirmation(email: String, password: String)
        case signedIn
    }

    @Published private(set) var state: State = .loading

    func bootstrap() async {
        #if DEBUG
        // Store-screenshot UI tests pass the real demo backend's
        // AppConfigJson this way (typing into the setup form is flaky in CI).
        if BackendConfigStore.load() == nil,
           let json = ProcessInfo.processInfo.environment["UITEST_CONFIG_JSON"],
           let config = BackendConfigStore.parse(json: json) {
            BackendConfigStore.save(config)
        }
        #endif

        // UI tests pass this flag to reach the sign-in screen without having
        // to type into the setup form (simulator typing is flaky in CI).
        if ProcessInfo.processInfo.arguments.contains("-uiTestPresetConfig"),
           BackendConfigStore.load() == nil {
            BackendConfigStore.save(
                BackendConfig(
                    apiBaseURL: URL(string: "https://example.execute-api.ap-northeast-1.amazonaws.com")!,
                    region: "ap-northeast-1",
                    clientId: "ui-test-client"
                )
            )
        }

        guard BackendConfigStore.load() != nil else {
            state = .needsSetup
            return
        }
        state = await TokenProvider.shared.isSignedIn() ? .signedIn : .signedOut
    }

    /// Saves the backend configuration entered in the setup screen and moves
    /// on to the sign-in screen.
    func applyConfig(_ config: BackendConfig) {
        BackendConfigStore.save(config)
        state = .signedOut
    }

    /// Clears the stored backend configuration (and any session) so the user
    /// can connect to a different AWS environment.
    func resetBackend() async {
        await TokenProvider.shared.signOut()
        BackendConfigStore.clear()
        state = .needsSetup
    }

    func signIn(email: String, password: String) async throws {
        do {
            let tokens = try await CognitoAuthClient.signIn(email: email, password: password)
            await TokenProvider.shared.store(tokens)
            state = .signedIn
        } catch let error as CognitoError where error.type == "UserNotConfirmedException" {
            state = .needsConfirmation(email: email, password: password)
            throw error
        }
    }

    func signUp(email: String, password: String) async throws {
        try await CognitoAuthClient.signUp(email: email, password: password)
        state = .needsConfirmation(email: email, password: password)
    }

    func confirmAndSignIn(code: String) async throws {
        guard case .needsConfirmation(let email, let password) = state else { return }
        try await CognitoAuthClient.confirmSignUp(email: email, code: code)
        try await signIn(email: email, password: password)
    }

    func cancelConfirmation() {
        state = .signedOut
    }

    func signOut() async {
        await TokenProvider.shared.signOut()
        state = .signedOut
    }

    /// Permanently deletes the Cognito account (App Store guideline 5.1.1(v)
    /// requires in-app account deletion). Local per-account records are
    /// cleared too; photos already in the user's own S3 bucket are untouched.
    func deleteAccount() async throws {
        do {
            let accessToken = try await TokenProvider.shared.validAccessToken()
            try await CognitoAuthClient.deleteUser(accessToken: accessToken)
        } catch let error as CognitoError where error.type == "NotAuthorizedException" {
            // Token revoked mid-flight — the session is unusable either way,
            // so fall through to the local sign-out and surface the error.
            await TokenProvider.shared.signOut()
            state = .signedOut
            throw error
        }
        await TokenProvider.shared.signOut()
        UploadHistoryStore.clear()
        UploadedAssetsStore.clear()
        UploadItemsSnapshotStore.clear()
        state = .signedOut
    }
}
