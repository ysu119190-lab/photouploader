# PhotoUploader — iPhone から AWS S3 に写真をアップロードするアプリ

SwiftUI 製の iOS アプリと、AWS SAM で構築するサーバーレスバックエンドのセットです。

## 仕組み(presigned URL 方式)

```
iPhone アプリ                AWS
┌──────────────┐   ①POST /presign    ┌─────────────┐
│ PhotoUploader │ ──────────────────▶ │ API Gateway  │
│  (SwiftUI)    │                     │   + Lambda   │
│               │ ◀────────────────── │              │
│               │   ②署名付きURLを返す  └──────┬──────┘
│               │                            │署名
│               │   ③PUT (写真データ)   ┌──────▼──────┐
│               │ ──────────────────▶ │  S3 バケット  │
└──────────────┘                     └─────────────┘
```

1. アプリが API に「アップロードしたい(contentType はこれ)」とリクエスト
2. Lambda が 15 分間有効な署名付き PUT URL を発行
3. アプリが写真データを S3 に直接 PUT

アプリは AWS の認証情報を一切持たず、写真データも Lambda を経由しないため、安全かつ大きなファイルでも高速です。

## リポジトリ構成

```
backend/               AWS SAM(S3 バケット + Lambda + API Gateway)
  template.yaml
  src/presign/app.py   署名付きURLを発行する Lambda
ios/                   iOS アプリ(XcodeGen で .xcodeproj を生成)
  project.yml
  PhotoUploader/       SwiftUI ソース一式
.github/workflows/     CI(SAM テンプレートの lint + iOS ビルド確認)
```

## セットアップ手順

### 前提

- AWS アカウントと [AWS CLI](https://docs.aws.amazon.com/cli/)(認証設定済み)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
- Mac + Xcode 15 以降
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)(`brew install xcodegen`)

### 1. バックエンドをデプロイ

```bash
# アプリが使う API キー(共有シークレット)を生成
openssl rand -hex 32
# → 表示された文字列を控えておく

cd backend
sam build
sam deploy --guided
#   Stack Name:        photo-uploader(任意)
#   Region:            ap-northeast-1(任意)
#   Parameter ApiKey:  ↑で生成した文字列を入力
#   その他はデフォルトで OK
```

デプロイ完了時に表示される **Outputs** の `ApiEndpoint` を控えます。

動作確認(curl):

```bash
curl -X POST "<ApiEndpoint>/presign" \
  -H "x-api-key: <生成したAPIキー>" \
  -H "Content-Type: application/json" \
  -d '{"contentType": "image/jpeg"}'
# → {"uploadUrl": "...", "key": "uploads/....jpg", "expiresIn": 900} が返れば OK

# 返ってきた uploadUrl に実際にアップロードしてみる
curl -X PUT "<uploadUrl>" -H "Content-Type: image/jpeg" --data-binary @test.jpg
```

### 2. iOS アプリをビルド

```bash
cd ios
xcodegen generate        # PhotoUploader.xcodeproj を生成
open PhotoUploader.xcodeproj
```

Xcode で以下を設定します:

1. `PhotoUploader/AppConfig.swift` を開き、`apiBaseURL` に `ApiEndpoint` の値、`apiKey` に生成した API キーを設定
2. Signing & Capabilities で自分の Team を選択(実機で動かす場合)
3. シミュレータまたは実機で Run

アプリの「写真を選択」から複数枚(枚数無制限)選ぶと、4 並列で S3 へアップロードされ、進捗と結果(S3 キー)が一覧に表示されます。

**バックグラウンドアップロード対応:** 転送は background `URLSession` 経由なので、ホーム画面に戻る・他のアプリに切り替える・画面をロックしても、送信済みキューに入った分は OS が転送を継続します。署名付き URL が転送待ちの間に失効した場合(HTTP 403)は、新しい URL を取得して自動リトライ(最大 3 回)します。

> **注意:**
> - 写真ライブラリからの読み出し・変換(キュー投入前の準備処理)はアプリが動いている間に行われます。バックグラウンド移行後は iOS が与える猶予時間(数十秒程度)で継続しますが、数百枚規模では全件のキュー投入前に停止する可能性があるため、投入が終わるまでは前面のままが確実です。
> - アプリスイッチャーから上スワイプで強制終了すると、バックグラウンド転送もキャンセルされます。
> - システムによる終了後もアップロード自体は完走しますが、進捗一覧の表示は再起動後には復元されません(履歴の永続化は「今後の拡張アイデア」参照)。

## アップロードされた写真の確認

```bash
aws s3 ls s3://<BucketName>/uploads/ --recursive
```

オブジェクトキーは `uploads/YYYY/MM/DD/<UUID>.<拡張子>` の形式です。

## セキュリティについて

- S3 バケットはパブリックアクセス全ブロック + サーバーサイド暗号化(SSE-S3)
- API は `x-api-key` ヘッダーの共有シークレットで保護(Lambda 側で検証)
- 署名付き URL は 1 時間で失効し、署名時に指定した Content-Type でしか PUT できません(失効時はアプリが新しい URL で自動リトライ)

本格運用する場合は、共有シークレットではなく **Sign in with Apple + Cognito** や **JWT オーソライザー** への置き換えを推奨します(アプリバイナリに埋め込んだキーは解析で抽出され得るため)。

## 今後の拡張アイデア

- カメラ撮影からの直接アップロード
- アップロード履歴の永続化(アプリ再起動後も進捗一覧を復元)
- アップロード済みの重複検出(同じ写真の二重バックアップ防止)
- アップロード済み写真の一覧・閲覧機能(S3 ListObjects + 署名付き GET URL)
- Cognito / Sign in with Apple による本格的な認証

## CI

GitHub Actions で push / PR ごとに以下を実行します:

- `cfn-lint` による SAM テンプレートの検証と Lambda ソースのコンパイルチェック
- macOS ランナーで XcodeGen → `xcodebuild` による iOS アプリのビルド確認
