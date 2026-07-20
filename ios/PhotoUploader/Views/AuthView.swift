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

    private enum ResetPhase {
        case none
        case request
        case confirm(email: String)
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationCode = ""
    @State private var resetPhase: ResetPhase = .none
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                if case .needsConfirmation(let pendingEmail, _) = session.state {
                    confirmationSections(for: pendingEmail)
                } else {
                    switch resetPhase {
                    case .none:
                        credentialSections
                    case .request:
                        resetRequestSections
                    case .confirm(let resetEmail):
                        resetConfirmSections(for: resetEmail)
                    }
                }

                if let infoMessage {
                    Section {
                        Text(infoMessage)
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
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
            .onAppear(perform: prefillForUITestsIfNeeded)
        }
    }

    /// Store-screenshot UI tests pass the demo account this way because
    /// typing into simulator text fields is flaky in CI.
    private func prefillForUITestsIfNeeded() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if email.isEmpty, let presetEmail = env["UITEST_PREFILL_EMAIL"] {
            email = presetEmail
            password = env["UITEST_PREFILL_PASSWORD"] ?? ""
        }
        #endif
    }

    @ViewBuilder
    private var credentialSections: some View {
        Section {
            LogoHeader(subtitle: "写真をあなたのAWSへバックアップ")
        }
        .listRowBackground(Color.clear)

        Section {
            Picker("モード", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("このアプリ専用のアカウントです(AWSのアカウントやApple IDとは関係ありません)。初めて使うときは「新規登録」でメールアドレスとパスワードを登録してください。")
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
                Text("登録したメールアドレスに確認コードが届きます(届かない場合は迷惑メールフォルダもご確認ください)")
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

        if mode == .signIn {
            Section {
                Button("パスワードを忘れた場合") {
                    errorMessage = nil
                    infoMessage = nil
                    resetPhase = .request
                }
                .font(.footnote)
            }
        }

        Section {
            Button("接続先の設定をやり直す") {
                errorMessage = nil
                Task { await session.resetBackend() }
            }
            .font(.footnote)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let host = BackendConfigStore.load()?.apiBaseURL.host() {
                    Text("現在の接続先: \(host)")
                }
                Text("接続設定は端末に保存済みなので、再入力は不要です。別のAWS環境につなぎ替えるときだけやり直してください。")
            }
        }
    }

    @ViewBuilder
    private var resetRequestSections: some View {
        Section {
            TextField("メールアドレス", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("パスワードのリセット")
        } footer: {
            Text("登録済みのメールアドレスに6桁のリセットコードを送ります")
        }

        Section {
            Button {
                requestPasswordReset()
            } label: {
                HStack {
                    Spacer()
                    if isBusy {
                        ProgressView()
                    } else {
                        Text("リセットコードを送信")
                    }
                    Spacer()
                }
            }
            .disabled(email.isEmpty)

            Button("キャンセル", role: .cancel) {
                errorMessage = nil
                resetPhase = .none
            }
        }
    }

    @ViewBuilder
    private func resetConfirmSections(for resetEmail: String) -> some View {
        Section {
            TextField("リセットコード", text: $resetCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            SecureField("新しいパスワード(8文字以上)", text: $newPassword)
                .textContentType(.newPassword)
        } header: {
            Text("新しいパスワードの設定")
        } footer: {
            Text("\(resetEmail) 宛てに送信された6桁のコードを入力してください。届かない場合は迷惑メールフォルダもご確認ください")
        }

        Section {
            Button {
                confirmPasswordReset(for: resetEmail)
            } label: {
                HStack {
                    Spacer()
                    if isBusy {
                        ProgressView()
                    } else {
                        Text("パスワードを変更する")
                    }
                    Spacer()
                }
            }
            .disabled(resetCode.isEmpty || newPassword.isEmpty)

            Button("キャンセル", role: .cancel) {
                errorMessage = nil
                resetCode = ""
                newPassword = ""
                resetPhase = .none
            }
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
            Text("\(pendingEmail) 宛てに送信された6桁のコードを入力してください。数分待っても届かない場合は、迷惑メールフォルダを確認してください(差出人: no-reply@verificationemail.com)")
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

    private func requestPasswordReset() {
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await CognitoAuthClient.forgotPassword(email: email)
                resetPhase = .confirm(email: email)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func confirmPasswordReset(for resetEmail: String) {
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await CognitoAuthClient.confirmForgotPassword(
                    email: resetEmail,
                    code: resetCode,
                    newPassword: newPassword
                )
                resetPhase = .none
                resetCode = ""
                newPassword = ""
                password = ""
                mode = .signIn
                infoMessage = "パスワードを変更しました。新しいパスワードでログインしてください"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitCredentials() {
        errorMessage = nil
        infoMessage = nil
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
