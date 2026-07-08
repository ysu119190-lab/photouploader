import SwiftUI

/// First-run screen where the user connects the app to their own AWS backend
/// by scanning a QR code, pasting the AppConfigJson stack output, or typing
/// the values manually.
struct SetupView: View {
    @ObservedObject var session: SessionStore

    @State private var pastedJSON = ""
    @State private var apiURLText = ""
    @State private var region = "ap-northeast-1"
    @State private var clientId = ""
    @State private var errorMessage: String?
    @State private var isShowingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("バックアップ先となる、あなたのAWS環境の情報を設定します。バックエンドのデプロイ完了時に表示される値を使ってください(README参照)。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if QRScannerView.isSupported {
                    Section {
                        Button {
                            isShowingScanner = true
                        } label: {
                            Label("QRコードを読み取る", systemImage: "qrcode.viewfinder")
                        }
                    } footer: {
                        Text("デプロイ結果の AppConfigJson から作ったQRコードをスキャンします")
                    }
                }

                Section("まとめて貼り付け") {
                    TextField("AppConfigJson の値を貼り付け", text: $pastedJSON, axis: .vertical)
                        .lineLimit(3...6)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("貼り付けた内容を読み込む") {
                        applyJSON(pastedJSON)
                    }
                    .disabled(pastedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("手動で入力") {
                    TextField("APIのURL", text: $apiURLText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("リージョン", text: $region)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("クライアントID", text: $clientId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("この内容で設定する") {
                        save()
                    }
                    .disabled(apiURLText.isEmpty || region.isEmpty || clientId.isEmpty)
                }
            }
            .navigationTitle("接続先の設定")
            .sheet(isPresented: $isShowingScanner) {
                QRScannerSheet { payload in
                    isShowingScanner = false
                    applyJSON(payload)
                }
            }
        }
    }

    private func applyJSON(_ text: String) {
        errorMessage = nil
        guard let config = BackendConfigStore.parse(json: text) else {
            errorMessage = "設定データを読み取れませんでした。AppConfigJson の値をそのまま使っているか確認してください"
            return
        }
        apiURLText = config.apiBaseURL.absoluteString
        region = config.region
        clientId = config.clientId
        session.applyConfig(config)
    }

    private func save() {
        errorMessage = nil
        let trimmedURL = apiURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme == "https" else {
            errorMessage = "APIのURLは https:// で始まる形式で入力してください"
            return
        }
        session.applyConfig(
            BackendConfig(
                apiBaseURL: url,
                region: region.trimmingCharacters(in: .whitespacesAndNewlines),
                clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }
}

#Preview {
    SetupView(session: SessionStore())
}
