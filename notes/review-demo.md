# App Store 審査用デモ環境の手順と Review Notes 下書き

審査員は自分でAWSバックエンドを構築しないため、**事前構築済みのデモスタックと
ログイン済みにできるテストアカウント**を提出時に添える。これが無いと
「起動しても何もできないアプリ」として 2.1(App Completeness)で即リジェクトされる。

状態: 手順とNotes文面は準備済み。スタックのデプロイとアカウント作成(下記 §1〜§2)は
AWSアカウントを持つ配布者(あなた)の作業。提出の数日前に実施する。

---

## 1. デモスタックのデプロイ(あなたの作業・15分)

1. 自分のAWSアカウントで、アプリ内「はじめてガイド」にも載せているクイック作成リンクを開く
   (または `backend/` から `sam deploy --guided`)
2. スタック名は `photouploader-review-demo` など**本番と区別できる名前**にする
3. `CREATE_COMPLETE` 後、「出力」タブの **AppConfigJson** の値を控える
   → これが Review Notes に貼る接続設定になる

> 💡 コストはほぼゼロ(審査員が数枚アップロードする程度)。**審査後も削除しない**こと。
> リジェクト→再審査やアップデート審査のたびに同じ環境を使い回せる。

## 2. 審査用テストアカウントの作成(あなたの作業・5分)

確認コードメールの手順を審査員にやらせないため、**確認済みのユーザーを事前に作る**。
スタックの「出力」から UserPoolId を控えて、AWS CLI で:

```bash
# 1) ユーザー作成(招待メールは送らない)
aws cognito-idp admin-create-user \
  --user-pool-id <UserPoolId> \
  --username review-demo@example.com \
  --user-attributes Name=email,Value=review-demo@example.com Name=email_verified,Value=true \
  --message-action SUPPRESS

# 2) パスワードを確定(FORCE_CHANGE_PASSWORD 状態を解除)
aws cognito-idp admin-set-user-password \
  --user-pool-id <UserPoolId> \
  --username review-demo@example.com \
  --password 'ReviewDemo2026!' \
  --permanent
```

作成後、**実機かシミュレータで一度この手順どおりにログインできることを必ず確認**する
(接続設定の貼り付け → ログイン → 写真を1枚アップロード → 保存済みタブで表示)。

## 3. App Store Connect への記入(あなたの作業・5分)

「App Review に関する情報」で:

- **サインイン情報が必要**: オン
  - ユーザー名: `review-demo@example.com`
  - パスワード: `ReviewDemo2026!`(§2で設定したもの)
- **メモ**: 下の Review Notes を貼り、`<AppConfigJson>` を §1 で控えた実際の値に置き換える
- **連絡先情報**: 自分の氏名・電話・メール

## 4. Review Notes 下書き(英語)

> This app backs up the user's photos/videos to the user's own AWS account
> (a "bring your own cloud" model, similar to self-hosted server clients).
> The developer operates no server: photos and credentials never reach us.
> Normally the user creates their own AWS backend with a provided one-click
> CloudFormation link at first launch.
>
> For review, please use our pre-built demo backend instead — no AWS account
> or setup is needed:
>
> 1. On the first-launch "接続先の設定" (Backend setup) screen, choose the
>    paste field ("まとめて貼り付け") and paste the following configuration
>    JSON, then tap the load button ("貼り付けた内容を読み込む"):
>
>    `<{"apiEndpoint":"https://0t0zusp3vb.execute-api.ap-northeast-1.amazonaws.com","region":"ap-northeast-1","clientId":"5ba7ku5qehtougs71b8agi9ov9"}>`
>
> 2. On the sign-in screen, log in with the demo account provided in the
>    App Review sign-in information (email/password above).
> 3. After the first sign-in, a one-time storage-mode chooser sheet appears.
>    Keep the default ("標準モード") and tap the confirm button
>    ("この設定ではじめる"). The fees it explains are AWS storage fees billed
>    to the user's own AWS account — the app itself has no in-app purchases.
> 4. Tap "写真・動画を選択" (top right) to pick photos — they upload to the
>    demo S3 bucket. The "保存済み" tab lists uploaded items; tapping one
>    shows it full-screen with a "save to device" (restore) option.
> 5. Account deletion (guideline 5.1.1(v)) is available from the
>    "アカウント" menu (top left) → "アカウントを削除".
> 6. Uploaded items can be deleted from the "保存済み" tab via "選択" —
>    they move to a server-side trash that auto-expires after 30 days.
>
> Notes:
> - Ads (banner, rewarded before uploads, and an app-open ad after
>   returning from background) are served by Google AdMob in
>   non-personalized mode only (npa=1); the app does not track users
>   and shows no ATT prompt.
> - The demo backend is a standard deployment of the same open-source
>   template every user deploys: https://github.com/ysu119190-lab/photouploader

## 5. 日本語メモ(自分用・審査で聞かれたときの回答方針)

- **「一般ユーザーはどう使うのか」** → 初回起動のはじめてガイドから、ブラウザだけで
  自分のAWSに保存先を構築できる(ワンクリック構築)。対象ユーザーは「自分のクラウドに
  写真を置きたい人」で、同型のアプリ(自前サーバー接続型)は既にストアに多数ある
- **「なぜアカウント登録が必要か」** → 保存先(利用者自身のAWS)へのアクセス制御のため。
  メールアドレスは利用者自身のAWS内のCognitoにのみ保存され、開発者は受け取らない
- **「広告とトラッキング」** → 非パーソナライズ広告のみ。App Privacy申告は
  `notes/app-privacy-label.md` の表のとおり

## 6. 提出前チェックリスト

- [x] デモスタックをデプロイし AppConfigJson を控えた(§1)(2026-07-19。スタック名 photouploader-review-demo / ap-northeast-1 / sam deploy --guided。審査後も削除しない)
- [x] テストアカウントを作成し、実際にログイン→アップロード→閲覧まで通した(§2)(2026-07-19。接続設定の貼り付け→ログイン→アップロード→保存済みタブ表示まで確認済み)
- [x] Review Notes の `<AppConfigJson>` を実値に置き換えた(§4)(§4の文面に反映済み。提出時はこの文面をそのままASCの「メモ」に貼る)
- [x] デモ用バケットに数枚アップロード済みにしておく(「保存済み」タブが空でないように)(2026-07-20。store-screenshotsワークフローが実行のたびに自動でアップロードする)
- [x] AdMobの本番ID設定(2026-07-15済み。ReleaseビルドはバナーリワードApp Openとも本番ID・NPA固定)
- [x] AdMob管理画面のEU同意設定がNPA運用に合っている(2026-07-19済み。GDPRメッセージをEEA・英国ターゲットで公開。UMP SDK未導入のためEEAでは広告非配信=NPA運用と矛盾なし)
- [x] ASCの「App Review に関する情報」を記入(2026-07-23)。サインイン情報(review-demo@example.com)・Review Notes(§4)・連絡先を登録
