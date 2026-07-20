import SwiftUI
import UIKit

/// Step-by-step first-time setup guide for users without AWS/GitHub
/// knowledge. Reached from the setup screen.
struct SetupGuideView: View {
    /// Absolute string of the link whose "copied!" feedback is showing.
    @State private var copiedURL: String?

    var body: some View {
        List {
            Section {
                Text("このアプリは、写真をあなた自身のAWS(Amazonのクラウドサービス)にバックアップします。最初に一度だけ「保存先」を作る必要があります。専門知識は不要で、所要時間は15分ほどです。")
                    .font(.callout)
            }

            Section("料金の目安") {
                Text("アプリは無料ですが、AWSの保存料が保存量に応じて毎月かかります(従量課金)。目安は写真100GBで、標準モードなら月400円程度、節約モードなら月75円程度です。数GB程度なら月数円〜数十円です。アップロード自体に通信料はかかりません。\n\nこの保存料はアプリへの支払いではなく、あなた自身のAWSアカウントにAWSから直接請求されます。このアプリにアプリ内課金や月額プランはありません。\n\nやめたくなったら、AWSの管理画面から写真(S3バケットの中身)と作成したスタックを削除すれば、以降の請求は止まります。アプリを消しただけではAWSの保存料は止まらない点にご注意ください。")
                    .font(.callout)
            }

            Section("ステップ 1: AWSアカウントを作る") {
                Text("AWSの無料アカウントを作成します(クレジットカードの登録が必要です)。すでに持っている場合はステップ2へ。")
                    .font(.callout)
                linkRow(
                    url: AppLinks.awsSignUpURL,
                    label: "AWSアカウント作成ページを開く",
                    systemImage: "person.badge.plus"
                )
            }

            Section {
                Text("下のボタンを押すとAWSの管理画面が開きます。ログイン後、ページ下部の確認チェックをすべてオンにして「スタックの作成」ボタンを押してください。3〜5分で自動的に完成します。")
                    .font(.callout)
                linkRow(
                    url: AppLinks.backendQuickCreateURL,
                    label: "保存先を作成する(ワンクリック構築)",
                    systemImage: "wand.and.stars"
                )
            } header: {
                Text("ステップ 2: 保存先をワンクリックで作る")
            } footer: {
                Text("パソコンのブラウザで作業したい場合は「リンクをコピー」でURLを控え、メールやメモでパソコンに送ってから開いてください。")
            }

            Section {
                Text("作成が終わると、ステータスが「CREATE_COMPLETE」(緑色)に変わります。接続設定は次の場所にあります。\n\n1. スタック名「photo-uploader」をタップして詳細画面を開く\n2. 画面上部のタブから「出力」を選ぶ(スマートフォンではタブが横スクロールで隠れていることがあります)\n3. キーが「AppConfigJson」の行を探し、「値」欄の { から } までの1行を丸ごとコピーする\n\nパソコンで作業した場合は、コピーした値をメールやメモでiPhoneに送ってください。")
                    .font(.callout)
            } header: {
                Text("ステップ 3: 接続設定をコピーする")
            } footer: {
                Text("「出力」タブが見つからない場合は、スタック一覧から photo-uploader を選び直してください。")
            }

            Section("ステップ 4: このアプリに貼り付ける") {
                Text("前の画面に戻り、「まとめて貼り付け」欄にコピーした値をペーストして「貼り付けた内容を読み込む」を押せば接続完了です。")
                    .font(.callout)
            }

            Section("ステップ 5: アカウント登録") {
                Text("最後に、ログイン画面の「新規登録」からメールアドレスとパスワード(8文字以上)を登録します。メールに届く6桁のコードを入力すれば、バックアップを始められます。コードのメールが届かない場合は、迷惑メールフォルダを確認してください(差出人: no-reply@verificationemail.com)。")
                    .font(.callout)
            }

            Section {
                Text("接続設定(AppConfigJson)は保存先を作ったAWSアカウントの管理画面でいつでも確認できます。下のボタンで CloudFormation を開き、スタック「photo-uploader」→「出力」タブの順にたどってください(ステップ3と同じ手順です)。機種変更後の再設定や、値を控え忘れたときもここから確認できます。")
                    .font(.callout)
                linkRow(
                    url: AppLinks.cloudFormationConsoleURL,
                    label: "AWS管理画面(CloudFormation)を開く",
                    systemImage: "doc.text.magnifyingglass"
                )
            } header: {
                Text("接続設定をあとから確認するには")
            } footer: {
                Text("現在アプリが接続しているサーバーは、ログイン画面下部の「現在の接続先」でも確認できます。")
            }
        }
        .navigationTitle("はじめてガイド")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A tappable link plus a "copy link" button. `Link` alone only opens the
    /// URL — there is no way to copy it — which blocks users who want to move
    /// the AWS console work to a PC. The copy button fills that gap and shows
    /// brief confirmation.
    @ViewBuilder
    private func linkRow(url: URL, label: String, systemImage: String) -> some View {
        Link(destination: url) {
            Label(label, systemImage: systemImage)
        }
        Button {
            UIPasteboard.general.string = url.absoluteString
            withAnimation { copiedURL = url.absoluteString }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if copiedURL == url.absoluteString {
                    withAnimation { copiedURL = nil }
                }
            }
        } label: {
            let copied = copiedURL == url.absoluteString
            Label(
                copied ? "コピーしました" : "リンクをコピー",
                systemImage: copied ? "checkmark" : "doc.on.doc"
            )
            .font(.callout)
            .foregroundStyle(copied ? Color.green : Color.accentColor)
        }
    }
}

#Preview {
    NavigationStack {
        SetupGuideView()
    }
}
