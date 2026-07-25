# 審査リジェクト対応: Guideline 2.1(a) — Information Needed(デモQRコード）

- Submission ID: 9bb7b427-c5db-457b-82b0-ef2093d88f45
- Review date: 2026-07-24 / Review Device: iPad Air 11-inch (M3) / Version: 1.0 (3)
- 指摘: "We need a demo QR code or AR marker (image) to fully assess the app features."

## 状況の読み解き

これは **2.1(a) Information Needed(情報の追加要求）**であり、ビルドの作り直しは不要。
本来は Resolution Center で情報（＝デモ用QR画像）を返信すれば同じビルド 1.0(3) の審査が再開する。

**※ 追記(2026-07-25): 提出(Submission)を誤って削除してしまった場合**
ASC の「提出内容」でステータスが「削除済み」になっているなら、審査から取り下げられた状態。
メッセージで返信する導線は使えないので、**新しい提出(Submission)を作り直して再提出**する
（下記 §7）。ビルドは既存の 1.0(3) をそのまま使え、アップロードは不要。デモ環境・QR・
アカウントは全てそのまま有効。

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

> This is a resubmission of version 1.0 (build 3), previously reviewed under
> Submission ID 9bb7b427-c5db-457b-82b0-ef2093d88f45, addressing the
> Guideline 2.1(a) request for a demo QR code. (The prior submission was
> withdrawn on our side; no app changes were made.)
>
> Here is the demo QR code you requested, plus a paste-based alternative in
> case scanning an on-screen code is inconvenient.
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

## 7. 提出(Submission)を削除してしまった場合の再提出手順

ASC の「提出内容」でステータスが **「削除済み」**＝審査から取り下げられている。
Resolution Center のやり取りも消えるが、**バージョン1.0・ビルド(3)・デモ環境・QR・
テストアカウントは全て残っている**ので、新しい提出を作り直すだけでよい。

1. アプリ → バージョン1.0ページを開く（提出削除で編集可能な状態に戻っているはず）。
2. **「App Review に関する情報」を整える**:
   - QR画像 `photouploader-review-demo-qr.png` を添付
   - メモ(Review Notes)= §4 の英文（冒頭に「これは前回 Submission ID 9bb7b427… の
     再提出」と明記済み）を貼る
   - サインイン情報 `review-demo@example.com` / `ReviewDemo2026!` が入っているか確認
   - 連絡先情報を確認
3. **新しい提出を作成 → バージョン1.0(ビルド3)を追加 → 審査に提出**。
   新しいビルドのアップロードは不要（既存ビルド3を使い回す）。
4. 新しい Submission ID が発番される。§4冒頭で旧IDを引用しているので審査員は経緯を追える。

> ⚠️ メールの「Reply to this message in App Store Connect」はメール返信では届かない。
> やり取りが消えている以上、返信ではなく上記の**再提出**で対応する。
</content>
