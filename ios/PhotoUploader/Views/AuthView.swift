import SwiftUI

/// Sign-in / sign-up / email-confirmation screen shown until the user is
/// authenticated.
struct AuthView: View {
    @ObservedObject var session: SessionStore

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "ログイン"
        case signUp = "新規登録"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationCode = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                if case .needsConfirmation(let pendingEmail, _) = session.state {
                    confirmationSections(for: pendingEmail)
                } else {
                    credentialSections
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("PhotoUploader")
            .disabled(isBusy)
        }
    }

    @ViewBuilder
    private var credentialSections: some View {
        Section {
            Picker("モード", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }

        Section {
            TextField("メールアドレス", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("パスワード(8文字以上)", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)
        } footer: {
            if mode == .signUp {
                Text("登録したメールアドレスに確認コードが届きます")
            }
        }

        Section {
            Button {
                submitCredentials()
            } label: {
                HStack {
                    Spacer()
                    if isBusy {
                        ProgressView()
                    } else {
                        Text(mode == .signIn ? "ログインする" : "登録する")
                    }
                    Spacer()
                }
            }
            .disabled(email.isEmpty || password.isEmpty)
        }

        Section {
            Button("接続先の設定をやり直す") {
                errorMessage = nil
                Task { await session.resetBackend() }
            }
            .font(.footnote)
        } footer: {
            Text("別のAWS環境に接続する場合はこちら")
        }
    }

    @ViewBuilder
    private func confirmationSections(for pendingEmail: String) -> some View {
        Section {
            TextField("確認コード", text: $confirmationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
        } header: {
            Text("メールの確認")
        } footer: {
            Text("\(pendingEmail) 宛てに送信された6桁のコードを入力してください")
        }

        Section {
            Button {
                submitConfirmationCode()
            } label: {
                HStack {
                    Spacer()
                    if isBusy {
                        ProgressView()
                    } else {
                        Text("確認する")
                    }
                    Spacer()
                }
            }
            .disabled(confirmationCode.isEmpty)

            Button("最初からやり直す", role: .cancel) {
                confirmationCode = ""
                errorMessage = nil
                session.cancelConfirmation()
            }
        }
    }

    private func submitCredentials() {
        errorMessage = nil
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                switch mode {
                case .signIn:
                    try await session.signIn(email: email, password: password)
                case .signUp:
                    try await session.signUp(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitConfirmationCode() {
        errorMessage = nil
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await session.confirmAndSignIn(code: confirmationCode)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AuthView(session: SessionStore())
}
