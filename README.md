# PhotoUploader — iPhone から AWS S3 に写真をアップロードするアプリ

SwiftUI 製の iOS アプリと、AWS SAM で構築するサーバーレスバックエンドのセットです。Cognito によるログイン機能付きで、ユーザーごとに専用のバックアップ領域に写真を保存します。

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

デプロイ完了時に表示される **Outputs** から次の 3 つを控えます:

- `ApiEndpoint`(API の URL)
- `UserPoolClientId`(Cognito アプリクライアント ID)
- `Region`(リージョン)

いずれも**秘密情報ではない**ので、リポジトリにコミットして問題ありません(API はログインで保護されています)。

### 2. アプリの接続先を設定

`ios/PhotoUploader/AppConfig.swift` の 3 つの値を、控えた Outputs の値に書き換えてコミットします(GitHub 上の編集でも OK):

```swift
static let apiBaseURL = URL(string: "<ApiEndpoint>")!
static let cognitoRegion = "<Region>"
static let cognitoClientId = "<UserPoolClientId>"
```

### 3. iOS アプリをビルド(Mac の場合)

```bash
cd ios
xcodegen generate        # PhotoUploader.xcodeproj を生成
open PhotoUploader.xcodeproj
```

実機で動かす場合は Signing & Capabilities で自分の Team を選択して Run。Mac がない場合は後述の「Mac がなくても試す方法」へ。

## アプリの使い方

1. 初回起動時にログイン画面が表示されます。「新規登録」でメールアドレスとパスワード(8文字以上)を登録
2. メールに届く 6 桁の確認コードを入力すると、自動でログインされます(次回以降は自動ログイン)
3. 「写真を選択」から複数枚(枚数無制限)選ぶと、4 並列で S3 へアップロードされ、進捗と結果が一覧に表示されます

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

## 今後の拡張アイデア

- カメラ撮影からの直接アップロード
- アップロード履歴の永続化(アプリ再起動後も進捗一覧を復元)
- アップロード済みの重複検出(同じ写真の二重バックアップ防止)
- アップロード済み写真の一覧・閲覧機能(S3 ListObjects + 署名付き GET URL)
- Sign in with Apple 対応(App Store 配信時に推奨)
- パスワードリセット(ForgotPassword)フロー

## CI

GitHub Actions で push / PR ごとに以下の 3 ジョブを実行します:

| ジョブ | 内容 | 成果物(Artifacts) |
|---|---|---|
| `backend-lint` | `cfn-lint` による SAM テンプレート検証 + Lambda のコンパイルチェック | — |
| `ios-simulator-test` | iOS シミュレータでアプリを起動して UI テストを実行 | `simulator-screenshots`(実行中の画面キャプチャ) |
| `ios-unsigned-ipa` | 実機向け未署名ビルドをパッケージ | `PhotoUploader-unsigned-ipa`(サイドロード用 .ipa) |

成果物は GitHub の **Actions → 該当の実行 → 画面下部の Artifacts** からダウンロードできます。

## Mac がなくても試す方法

### 画面の確認(スクリーンショット)

push するたびに CI がシミュレータ上でアプリを実際に起動し、スクリーンショットを撮ります。`simulator-screenshots` Artifact を開くと、ログイン画面と新規登録画面が確認できます。

### 実機での利用(AltStore / Windows)

Apple Developer Program に加入していなくても、Windows パソコンがあれば [AltStore](https://altstore.io/) で自分の iPhone にインストールできます:

1. **事前準備:** 上記「セットアップ手順 2」のとおり `AppConfig.swift` にデプロイ結果の値を設定してコミットしておく(CI がビルドする .ipa にその値が焼き込まれます。いずれも秘密情報ではありません)
2. Windows に [AltServer](https://altstore.io/) をインストール(iTunes / iCloud の**非 Microsoft Store 版**が必要)
3. iPhone を USB 接続し、AltServer から AltStore を iPhone にインストール
4. CI の `PhotoUploader-unsigned-ipa` Artifact をダウンロード・解凍し、.ipa を iPhone に転送(またはブラウザでダウンロード)
5. iPhone の AltStore アプリで「+」→ .ipa を選択 → 無料の Apple ID で署名されてインストール完了

**制限事項(無料 Apple ID の場合):** 署名の有効期限が 7 日間のため、週 1 回 AltStore での更新(Refresh)が必要です。同時にサイドロードできるアプリは 3 つまで。常用するなら Apple Developer Program($99/年)+ TestFlight 配信への移行がおすすめです。
