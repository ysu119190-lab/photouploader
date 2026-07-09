# PhotoUploader — iPhone から AWS S3 に写真をアップロードするアプリ

SwiftUI 製の iOS アプリと、AWS SAM で構築するサーバーレスバックエンドのセットです。Cognito によるログイン機能付きで、ユーザーごとに専用のバックアップ領域に写真を保存します。

アプリ自体には接続先が焼き込まれておらず、**初回起動時の設定画面で自分のAWS環境を登録する**方式です(QRコード読み取り/JSON貼り付け/手動入力)。各ユーザーが自分のAWSアカウントにバックエンドをデプロイして使う「持ち込みAWS」モデルなので、同じアプリバイナリを誰にでも配布できます。

## 仕組み(Cognito 認証 + presigned URL 方式)

```
iPhone アプリ                     AWS
┌──────────────┐  ①新規登録/ログイン  ┌─────────────┐
│ PhotoUploader │ ──────────────────▶ │   Cognito    │
│  (SwiftUI)    │ ◀────────────────── │ ユーザープール │
│               │   ②IDトークンを取得   └─────────────┘
│               │
│               │  ③POST /presign     ┌─────────────┐
│               │   (Bearer トークン)   │ API Gateway  │
│               │ ──────────────────▶ │ (JWT検証)     │
│               │ ◀────────────────── │   + Lambda   │
│               │   ④署名付きURLを返す  └──────┬──────┘
│               │                            │署名
│               │   ⑤PUT (写真データ)   ┌──────▼──────┐
│               │ ──────────────────▶ │  S3 バケット  │
└──────────────┘                     └─────────────┘
```

1. アプリ内でメールアドレス+パスワードで新規登録(メールに届く確認コードで本人確認)またはログイン
2. Cognito が発行するトークンを Keychain に保存(以後は自動ログイン・自動更新)
3. アプリが API に「アップロードしたい」とリクエスト(API Gateway がトークンを検証)
4. Lambda が 1 時間有効な署名付き PUT URL を発行(保存先はユーザーごとの領域)
5. アプリが写真データを S3 に直接 PUT

アプリは AWS の認証情報を一切持たず、写真データも Lambda を経由しないため、安全かつ大きなファイルでも高速です。

## リポジトリ構成

```
backend/               AWS SAM(Cognito + S3 バケット + Lambda + API Gateway)
  template.yaml
  src/presign/app.py   署名付きURLを発行する Lambda
ios/                   iOS アプリ(XcodeGen で .xcodeproj を生成)
  project.yml
  PhotoUploader/       SwiftUI ソース一式
  PhotoUploaderUITests/  シミュレータ用 UI テスト(CI でスクリーンショット取得)
.github/workflows/     CI(lint / シミュレータ UI テスト / .ipa 生成)
```

## セットアップ手順

> **一般の利用者に配布する場合**は、下の「[ワンクリック構築(クイック作成リンク)](#ワンクリック構築クイック作成リンク)」を参照してください。git や SAM CLI なしで、ブラウザだけでバックエンドを構築できます。以下は開発者向けの手順です。

### 前提

- AWS アカウントと [AWS CLI](https://docs.aws.amazon.com/cli/)(認証設定済み)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)(Windows でも動きます)
- (Mac でビルドする場合)Xcode 15 以降 + [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### 1. バックエンドをデプロイ

```bash
cd backend
sam build
sam deploy --guided
#   Stack Name: photo-uploader(任意)
#   Region:     ap-northeast-1(任意)
#   その他はデフォルトで OK
```

デプロイが終わったら、同じ `backend` フォルダで**設定表示スクリプト**を実行します:

```powershell
# Windows (PowerShell)
.\show-config.ps1
```

```bash
# Mac / Linux
./show-config.sh
```

スクリプトが以下を行います:

- アプリに貼り付ける値(1行の JSON)を **「ここから」「ここまで」で囲んで表示**(その間を丸ごとコピー)
- **QRコード付きの HTML(`app-config-qr.html`)を自動生成してブラウザで開く** → アプリでスキャンするだけ

表示される値はこのような1行の JSON で、いずれも**秘密情報ではありません**(API はログインで保護されています):

```json
{"apiEndpoint":"https://xxxx.execute-api.ap-northeast-1.amazonaws.com","region":"ap-northeast-1","clientId":"xxxxxxxx"}
```

### 2. アプリの接続先を設定(アプリ内で完結)

アプリの初回起動時に「接続先の設定」画面が表示されるので、次のいずれかで設定します:

- **QRコード**: スクリプトが開いた `app-config-qr.html` の QR をアプリでスキャン(いちばん簡単)
- **貼り付け**: 表示された JSON をそのまま「まとめて貼り付け」欄にペースト
- **手動入力**: URL・リージョン・クライアント ID を個別に入力

設定は端末内に保存され、初回の一度だけで済みます(アプリを更新しても保持されます。消えるのはアプリを削除したときだけ)。

### 3. iOS アプリをビルド(Mac の場合)

```bash
cd ios
xcodegen generate        # PhotoUploader.xcodeproj を生成
open PhotoUploader.xcodeproj
```

実機で動かす場合は Signing & Capabilities で自分の Team を選択して Run。Mac がない場合は後述の「Mac がなくても試す方法」へ。

## ワンクリック構築(クイック作成リンク)

一般の利用者(git や SAM CLI を知らない人)向けに、**ブラウザだけでバックエンドを構築できるリンク**を発行できます。

### 配布者(あなた)が一度だけやること

```powershell
# Windows (PowerShell) — バケット名は世界で一意の名前に
cd backend
.\publish-template.ps1 -BucketName photouploader-template-yourname
```

```bash
# Mac / Linux
cd backend
./publish-template.sh photouploader-template-yourname
```

スクリプトが単体テンプレート(`template-quickcreate.yaml`)をあなたの S3 に公開アップロードし、**利用者に配る「クイック作成リンク」**を表示します(テンプレートに秘密情報は含まれません)。バックエンドを更新したら再実行すればリンクはそのままで中身が更新されます。

発行したリンクは **アプリ内の「はじめてガイド」にも埋め込まれています**(`ios/PhotoUploader/AppLinks.swift` の `backendQuickCreateURL`)。テンプレートを別のバケット/リージョンに公開し直した場合は、この URL も更新してください。

### 利用者がやること(git・コマンド不要)

1. [AWS アカウントを作成](https://aws.amazon.com/jp/register-flow/)(無料。クレジットカード登録が必要)
2. 配布された**クイック作成リンク**を開く(AWSコンソールへのログインを求められたらログイン)
3. ページ下部の**承認チェックボックス**(IAM リソース作成と機能の承認)をオンにして「**スタックの作成**」を押す
4. 3〜5分待って状態が `CREATE_COMPLETE` になったら、「**出力**」タブを開き **AppConfigJson** の値をコピー
5. iPhone アプリの「接続先の設定」画面の「まとめて貼り付け」にペースト(またはQR化してスキャン)

## アプリの使い方

1. 初回起動時に「接続先の設定」画面が表示されます。QRコード/貼り付け/手動入力で自分のAWS環境を登録(一度だけ)
2. ログイン画面で「新規登録」からメールアドレスとパスワード(8文字以上)を登録(**このアプリ専用のアカウント**です。AWSアカウントやApple IDとは関係ありません)
3. メールに届く 6 桁の確認コードを入力すると、自動でログインされます(次回以降は自動ログイン)
4. 「写真を選択」から複数枚(枚数無制限)選ぶと、4 並列で S3 へアップロードされ、進捗が表示されます
5. アップロードが終わると **操作1回ごとの履歴**(日時・枚数・成否)が残ります
6. **一度アップロードした写真は自動でスキップ**されるので、同じ写真を選び直しても二重にバックアップされません

別のAWS環境につなぎ直したい場合は、ログイン画面の「接続先の設定をやり直す」から再設定できます。パスワードを忘れた場合は、ログイン画面の「パスワードを忘れた場合」からメールのリセットコードで再設定できます。

**保存済み写真の閲覧:** 「保存済み」タブで、アップロード済みの写真を新しい順のグリッドで一覧できます(タップで拡大表示、下に引っ張って更新)。表示は S3 への署名付き GET URL 経由で、写真データがサーバーを経由することはありません。

**保存モード(料金の最適化):** バックアップタブ右上の歯車から「標準」「節約」を選べます。標準は S3 Standard(すぐ表示・保存料高め)、節約は S3 Glacier Instant Retrieval(保存料が約1/5・表示は同じく一瞬・表示ごとに少額の取り出し料金)。バックアップ用途なら節約モードがおすすめです。選択は以降のアップロードに適用され、過去分は変わりません。

**バックグラウンドアップロード対応:** 転送は background `URLSession` 経由なので、ホーム画面に戻る・他のアプリに切り替える・画面をロックしても、送信済みキューに入った分は OS が転送を継続します。署名付き URL が転送待ちの間に失効した場合(HTTP 403)は、新しい URL を取得して自動リトライ(最大 3 回)します。トークンの有効期限が切れていても、Keychain のリフレッシュトークンで自動更新されます。

> **注意:**
> - 写真ライブラリからの読み出し・変換(キュー投入前の準備処理)はアプリが動いている間に行われます。数百枚規模では、キュー投入が終わるまで前面のままが確実です。
> - アプリスイッチャーから上スワイプで強制終了すると、バックグラウンド転送もキャンセルされます。
> - システムによる終了後もアップロード自体は完走しますが、進捗一覧の表示は再起動後には復元されません。

## アップロードされた写真の確認

```bash
aws s3 ls s3://<BucketName>/uploads/ --recursive
```

オブジェクトキーは `uploads/<ユーザーID>/YYYY/MM/DD/<UUID>.<拡張子>` の形式で、ユーザーごとに領域が分かれます。

API を直接試したい場合(トークンの取得には AWS CLI が使えます):

```bash
TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id <UserPoolClientId> \
  --auth-parameters USERNAME=<メールアドレス>,PASSWORD=<パスワード> \
  --query 'AuthenticationResult.IdToken' --output text)

curl -X POST "<ApiEndpoint>/presign" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"contentType": "image/jpeg"}'
```

## セキュリティについて

- API は Cognito の **JWT オーソライザー**で保護。ログインしたユーザーしか署名付き URL を取得できず、共有シークレットはリポジトリにもアプリにも存在しません
- 各ユーザーのアップロード先は自分の `uploads/<ユーザーID>/` 配下に限定されます
- トークンは iPhone の **Keychain**(OS の暗号化ストレージ)に保存され、失効時は自動更新
- S3 バケットはパブリックアクセス全ブロック + サーバーサイド暗号化(SSE-S3)
- 署名付き URL は 1 時間で失効し、署名時に指定した Content-Type でしか PUT できません

> パスワード認証には `USER_PASSWORD_AUTH` フロー(TLS 経由でパスワード送信)を使っています。SRP 化や Sign in with Apple 対応は今後の拡張候補です。

## 広告(AdMob)

2種類の広告を組み込んでいます。現在は **Google 公式のテスト用 ID** が設定されており、サンプル広告が表示されるだけで収益は発生しません(テスト ID のまま本番配信するのは AdMob 規約違反なので注意)。

- **バナー広告**: メイン画面の下部に常時表示(320×50)
- **リワード広告**: 写真を選んでアップロードを開始する直前に動画広告を表示し、視聴後にアップロードが始まります。広告が用意できない場合(オフライン・在庫なし)は**広告なしでそのままアップロードが始まる**設計です(バックアップ機能を広告の都合でブロックしないため)

**本番化の手順(App Store 公開時):**

1. [AdMob](https://admob.google.com/) アカウントを作成し、アプリを登録
2. 発行された**アプリ ID** を `ios/project.yml` の `GADApplicationIdentifier` に設定
3. バナーとリワードの広告ユニットを作成し、それぞれの **広告ユニット ID** を `ios/PhotoUploader/Services/AdsConfig.swift` の `bannerAdUnitID` / `rewardedAdUnitID` に設定
4. `SKAdNetworkItems` に [Google 推奨の SKAdNetwork ID 一覧](https://developers.google.com/admob/ios/quick-start#update_your_infoplist)を追加
5. 広告のパーソナライズを行う場合は ATT(App Tracking Transparency)対応と `NSUserTrackingUsageDescription` の追加を検討

なお、AdMob の収益化は実質的に App Store で公開されたアプリが前提です(AltStore 等のサイドロード配布では審査・収益化ができません)。

## 今後の拡張アイデア

- カメラ撮影からの直接アップロード
- アップロード履歴の永続化(アプリ再起動後も進捗一覧を復元)
- アップロード済みの重複検出(同じ写真の二重バックアップ防止)
- アップロード済み写真の一覧・閲覧機能(S3 ListObjects + 署名付き GET URL)
- Sign in with Apple 対応(App Store 配信時に推奨)
- パスワードリセット(ForgotPassword)フロー

## CI

GitHub Actions で **プルリクエスト単位**(PR の作成・更新ごと)と **main へのマージ時**に以下の 3 ジョブを実行します。同じ PR に続けて push した場合は古い実行を自動キャンセルし、最新のコミットだけを検証します:

| ジョブ | 内容 | 成果物(Artifacts) |
|---|---|---|
| `backend-lint` | `cfn-lint` による SAM テンプレート検証 + Lambda のコンパイルチェック | — |
| `ios-simulator-test` | iOS シミュレータでアプリを起動して UI テストを実行 | `simulator-screenshots`(実行中の画面キャプチャ) |
| `ios-unsigned-ipa` | 実機向け未署名ビルドをパッケージ | `PhotoUploader-unsigned-ipa`(サイドロード用 .ipa) |

成果物は GitHub の **Actions → 該当の実行 → 画面下部の Artifacts** からダウンロードできます。

## Mac がなくても試す方法

### 画面の確認(スクリーンショット)

PR を作成・更新するたびに CI がシミュレータ上でアプリを実際に起動し、スクリーンショットを撮ります。`simulator-screenshots` Artifact を開くと、接続先設定画面・ログイン画面・新規登録画面が確認できます。

### 実機での利用(AltStore / Windows)

Apple Developer Program に加入していなくても、Windows パソコンがあれば [AltStore](https://altstore.io/) で自分の iPhone にインストールできます:

1. Windows に [AltServer](https://altstore.io/) をインストール(iTunes / iCloud の**非 Microsoft Store 版**が必要)
2. iPhone を USB 接続し、AltServer から AltStore を iPhone にインストール
3. CI の `PhotoUploader-unsigned-ipa` Artifact をダウンロード・解凍し、.ipa を iPhone に転送(またはブラウザでダウンロード)
4. iPhone の AltStore アプリで「+」→ .ipa を選択 → 無料の Apple ID で署名されてインストール完了
5. アプリを起動し、「接続先の設定」画面で自分のAWS環境を登録(接続先はアプリ内で設定するので、.ipa は誰の環境の情報も含まない汎用バイナリです)

**制限事項(無料 Apple ID の場合):** 署名の有効期限が 7 日間のため、週 1 回 AltStore での更新(Refresh)が必要です。同時にサイドロードできるアプリは 3 つまで。常用するなら Apple Developer Program($99/年)+ TestFlight 配信への移行がおすすめです。

## 紹介ページ(ランディングページ)

`docs/` にランディングページ(`index.html`)とプライバシーポリシー(`privacy.html`)を用意しています。GitHub Pages でそのまま公開できます。

**公開手順:**

1. GitHub リポジトリの **Settings → Pages** を開く
2. **Source** を「Deploy from a branch」、**Branch** を `main` の `/docs` フォルダに設定して保存
3. 数分後、`https://<ユーザー名>.github.io/<リポジトリ名>/` で公開されます

公開前に、`docs/index.html`(フッターなど)と `docs/privacy.html` の角かっこ ［ ］(提供者名・連絡先・公開日)を埋めてください。公開後の `privacy.html` の URL は、App Store 申請時の「プライバシーポリシー URL」に使えます。

> 開発用のメモ(`notes/`)は Pages で公開されないよう `docs/` の外に置いています。

## ドキュメント

- `notes/PROJECT_NOTES.md` — 実装済み機能・課題の記録・今後のタスク
- `notes/zenn-article.md` — 技術記事の下書き
- `notes/privacy-policy.md` — プライバシーポリシー(Markdown 版。Web 版は `docs/privacy.html`)
