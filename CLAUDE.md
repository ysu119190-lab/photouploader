# CLAUDE.md

このリポジトリで Claude Code が作業するときの運用ルール。
`##  汎用ルール` は他リポジトリにもそのままコピーして使える。
`## このリポジトリ固有` は PhotoUploader 専用。

---

## 汎用ルール（他リポジトリにもコピー可）

### ブランチと main 開発

- **main へ直接 push しない。** 変更は必ず専用の作業ブランチで行う。
- 作業ブランチにコミットし、`git push -u origin <branch-name>` で push する。
- **main への反映は必ず Pull Request 経由。** PR の作成・マージは
  **ユーザーが明示的に依頼したときだけ**行う（勝手に作らない・マージしない）。
- **PR がマージされたら、同じブランチに新しいコミットを積み続けない。**
  追加作業は最新の main からブランチを作り直してから始める
  （`git fetch origin main && git checkout -B <branch> origin/main`）。
  マージ済み履歴の上に積むと、取り残しやコンフリクトの原因になる。

### push / fetch

- push は `git push -u origin <branch-name>`。
- **ネットワークエラーのときだけ**、指数バックオフで最大4回リトライ（2s→4s→8s→16s）。
  ネットワーク以外の失敗（rejected 等）はリトライせず原因を確認する。
- fetch/pull は対象ブランチを明示（`git fetch origin <branch>`）。

### コミット

- author / committer は **noreply アドレス**に統一する
  （`Claude <noreply@anthropic.com>`）。GitHub のメール非公開設定が有効だと、
  実メールでの push は `GH007` で拒否されるため。
- コミットメッセージは**日本語で簡潔・具体的に**。1行目に要約、必要なら本文で理由を書く。
- **1つのコミットは1つの意味のまとまり**にする（ドキュメントとコードは混ぜてよいが、
  無関係な変更は分ける）。

### 秘密情報の扱い

- **秘密鍵・証明書・パスワード・APIキー（.p8 / .p12 等）をチャットに貼らない。**
  値は GitHub の Settings → Secrets and variables → Actions に**直接**登録する。
- うっかり貼ってしまったら、**即座に失効させて再発行**する。
- **リポジトリやアプリバイナリに秘密を埋め込まない。** 認証は都度取得する方式にする。

### 作業の記録

- 実装・課題・今後のタスクは `notes/PROJECT_NOTES.md` に集約する（無ければ作る）。
  **セッション開始時にまず読み**、作業後に更新する。得られた教訓もここに残す。

---

## このリポジトリ固有（PhotoUploader）

### 概要

iPhone の写真・動画を「利用者自身の AWS（S3/Cognito）」にバックアップする
iOS アプリ（SwiftUI）＋サーバーレスバックエンド（AWS SAM）。開発者はサーバーを
持たない BYO-AWS 構成。詳細は `README.md` と `notes/PROJECT_NOTES.md`。

- `ios/` — アプリ（XcodeGen で `.xcodeproj` 生成。`project.yml` が正）
- `backend/` — SAM（Lambda は Python）。`template.yaml` と quickcreate 版の同期を CI が検査
- `docs/` — GitHub Pages（LP・プライバシーポリシー・app-ads.txt）
- `notes/` — 開発ノート・審査/ストア素材（Pages では公開されない）

### CI（`.github/workflows/`）

- **CI は PR 単位で起動**（作成・更新ごと）＋ **main への push 時**。
  **ブランチへの push だけでは起動しない。** マージ前の検証は PR を作って行う。
- 同一 PR への連続 push は `concurrency` で古い実行を自動キャンセル（`cancel-in-progress`）。
- **macOS ランナーは無料枠を10倍消費する。** 上記の PR 単位＋自動キャンセルを崩さない。
- `ci.yml` = backend-lint / ios-simulator-test / ios-unsigned-ipa。
  `testflight.yml` と `store-screenshots.yml` は **手動実行（workflow_dispatch）**。

### iOS / ビルドの注意（過去の障害から）

- **シミュレータの機種名をハードコードしない。** ランナーイメージ更新で機種が消える。
  ランタイムの対応機種から動的に選んで作成する。
- **App Store Connect へのアップロードは Xcode 26（iOS 26 SDK）以降が必須。**
  ワークフローで Xcode バージョンを明示選択する。
- iPhone 専用。`TARGETED_DEVICE_FAMILY: "1"` は**アプリターゲット自身**に設定する
  （XcodeGen の iOS プリセットがターゲットに `"1,2"` を入れるため、プロジェクトレベル
  設定では勝てない）。
- 全画面 UI（広告など）の present は、前面のシート遷移が完全に終わってから行う。
- 本番の広告 ID を Debug ビルドに入れない（`#if DEBUG` でテスト ID に切替。無効トラフィック対策）。

### TestFlight / 配信

- TestFlight ワークフローは **main から手動実行**（Actions → TestFlight → Run workflow）。
  ビルド番号は run number で単調増加、マーケティングバージョンは `ios/project.yml`。
- `.p12`（配布証明書）は **レガシー形式**でエクスポートしないと macOS ランナーが読めない
  （`openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1`）。

### セッション運用（トークン節約）

- 新しい作業は新セッションで始め、最初に `notes/PROJECT_NOTES.md` を読ませて引き継ぐ。
- CI の失敗はログ本文を貼らず **run の URL** を渡す。
- 並列サブエージェントは使わない。
