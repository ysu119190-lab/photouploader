import SwiftUI

/// Step-by-step first-time setup guide for users without AWS/GitHub
/// knowledge. Reached from the setup screen.
struct SetupGuideView: View {
    var body: some View {
        List {
            Section {
                Text("このアプリは、写真をあなた自身のAWS(Amazonのクラウドサービス)にバックアップします。最初に一度だけ「保存先」を作る必要があります。専門知識は不要で、所要時間は15分ほどです。料金は保存した写真の分だけAWSから請求されます(写真100GBで月400円程度)。")
                    .font(.callout)
            }

            Section("ステップ 1: AWSアカウントを作る") {
                Text("AWSの無料アカウントを作成します(クレジットカードの登録が必要です)。すでに持っている場合はステップ2へ。")
                    .font(.callout)
                Link(destination: AppLinks.awsSignUpURL) {
                    Label("AWSアカウント作成ページを開く", systemImage: "person.badge.plus")
                }
            }

            Section("ステップ 2: 保存先をワンクリックで作る") {
                Text("下のボタンを押すとAWSの管理画面が開きます。ログイン後、ページ下部の確認チェックをすべてオンにして「スタックの作成」ボタンを押してください。3〜5分で自動的に完成します。")
                    .font(.callout)
                Link(destination: AppLinks.backendQuickCreateURL) {
                    Label("保存先を作成する(ワンクリック構築)", systemImage: "wand.and.stars")
                }
            }

            Section("ステップ 3: 接続設定をコピーする") {
                Text("作成が終わる(ステータスが CREATE_COMPLETE になる)と「出力」タブに AppConfigJson という項目が現れます。その値({ から } までの1行)をコピーしてください。パソコンで作業した場合は、メールやメモでiPhoneに送ってください。")
                    .font(.callout)
            }

            Section("ステップ 4: このアプリに貼り付ける") {
                Text("前の画面に戻り、「まとめて貼り付け」欄にコピーした値をペーストして「貼り付けた内容を読み込む」を押せば接続完了です。")
                    .font(.callout)
            }

            Section("ステップ 5: アカウント登録") {
                Text("最後に、ログイン画面の「新規登録」からメールアドレスとパスワード(8文字以上)を登録します。メールに届く6桁のコードを入力すれば、バックアップを始められます。")
                    .font(.callout)
            }
        }
        .navigationTitle("はじめてガイド")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SetupGuideView()
    }
}
