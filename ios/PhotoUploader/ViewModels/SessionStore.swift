import SwiftUI

/// Drives the app's authentication state: signed out → (sign-up →
/// email-code confirmation →) signed in.
@MainActor
final class SessionStore: ObservableObject {
    enum State {
        case loading
        case signedOut
        /// Waiting for the email confirmation code. The password is kept so
        /// the app can sign in automatically right after confirmation.
        case needsConfirmation(email: String, password: String)
        case signedIn
    }

    @Published private(set) var state: State = .loading

    func bootstrap() async {
        state = await TokenProvider.shared.isSignedIn() ? .signedIn : .signedOut
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
}
