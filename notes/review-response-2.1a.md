# 審査リジェクト対応: Guideline 2.1(a) — Information Needed(デモQRコード）

- Submission ID: 9bb7b427-c5db-457b-82b0-ef2093d88f45
- Review date: 2026-07-24 / Review Device: iPad Air 11-inch (M3) / Version: 1.0 (3)
- 指摘: "We need a demo QR code or AR marker (image) to fully assess the app features."

## 状況の読み解き

これは **2.1(a) Information Needed(情報の追加要求）**であり、ビルドの作り直しは不要。
Resolution Center で情報（＝デモ用QR画像）を返信すれば、同じビルド 1.0(3) の審査が再開する。

本アプリの初回セットアップ画面（接続先の設定）は **QRスキャン / JSON貼り付け / 手動入力**の
3択で、先頭がQRスキャン。審査員はQRスキャン導線を試したが読み取る画像が無く、
テンプレ文言（"demo QR code or AR marker"）で画像の提出を求めてきた、という解釈が自然。

前回提出時は Review Notes に **貼り付け用JSON**とデモログインを載せた（`review-demo.md §4`）が、
**スキャン用のQR画像そのもの**は添えていなかった。今回はそれを渡す。

QRのペイロードは `AppConfigJson` の文字列そのまま（アプリは読み取り文字列を
`BackendConfig.parse` に渡すだけ。`QRScannerView.swift` / `BackendConfig.swift` で確認）。
デモスタック（`photouploader-review-demo` / ap-northeast-1）は削除していないのでそのまま使える。

## あなたの作業（ビルド不要・ASCで完結）

1. 生成済みQR画像 `photouploader-review-demo-qr.png`（デモ設定JSONをエンコード。
   スキャン→デコードで元JSONに戻ることを検証済み）を、Resolution Center の返信に添付する。
   - ASC の「App Review に関する情報 → 添付ファイル（Attachment）」にも同じ画像を入れておくと確実。
2. 下の英文返信を Resolution Center に貼る。
3. 送信後、審査再開を待つ（新しいビルドのアップロードは不要）。
4. サインイン情報（`review-demo@example.com` / `ReviewDemo2026!`）は前回登録済みのまま。
   念のため返信本文にも再掲する。

> QR画像を作り直したいときは、デプロイ済みスタックから:
> `backend/show-config.sh photouploader-review-demo`（QR付きHTMLを生成）
> または `notes/` の生成コマンド（segno）で `AppConfigJson` を再エンコードする。

## Resolution Center への返信（英語・そのまま貼れる）

> Thank you for the review. Here is the demo QR code you requested, plus a
> paste-based alternative in case scanning an on-screen code is inconvenient.
>
> This app backs up the user's photos/videos to the user's *own* AWS account
> (a "bring your own cloud" model, like self-hosted server clients). We operate
> no server, so at first launch the app must be pointed at a backend. For your
> review we provide a pre-built demo backend — no AWS account or setup needed.
>
> How to configure and test:
>
> 1. On the first-launch "接続先の設定" (Backend setup) screen, tap
>    "QRコードを読み取る" (Scan QR code) and scan the attached QR image
>    (photouploader-review-demo-qr.png). This fills in the demo backend
>    connection automatically.
>    - Alternative without a camera: choose the paste field
>      ("まとめて貼り付け"), paste the JSON below, then tap
>      "貼り付けた内容を読み込む":
>      {"apiEndpoint":"https://0t0zusp3vb.execute-api.ap-northeast-1.amazonaws.com","region":"ap-northeast-1","clientId":"5ba7ku5qehtougs71b8agi9ov9"}
>
> 2. On the sign-in screen, log in with the demo account (also in the App
>    Review sign-in information):
>      Email: review-demo@example.com
>      Password: ReviewDemo2026!
>
> 3. After the first sign-in, a one-time storage-mode chooser appears. Keep the
>    default ("標準モード") and tap "この設定ではじめる". The fees it mentions are
>    AWS storage fees billed to the user's own AWS account — the app itself has
>    no in-app purchases.
>
> 4. Tap "写真・動画を選択" (top right) to pick and upload photos to the demo
>    S3 bucket. The "保存済み" tab lists uploaded items; tapping one shows it
>    full-screen with a "save to device" option. Account deletion (guideline
>    5.1.1(v)) is under the "アカウント" menu (top left).
>
> Notes: Ads (banner / rewarded / app-open) are served by Google AdMob in
> non-personalized mode only (npa=1); the app does not track users and shows no
> ATT prompt. The demo backend is a standard deployment of the same open-source
> template every user deploys:
> https://github.com/ysu119190-lab/photouploader
>
> Please let us know if anything else is needed to complete the assessment.
</content>
