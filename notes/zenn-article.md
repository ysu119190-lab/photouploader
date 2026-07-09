---
title: "写真を「自分のAWS」にバックアップするiOSアプリを作った — 持ち込みAWSモデルの設計と実装"
emoji: "📸"
type: "tech"
topics: ["ios", "swift", "aws", "swiftui", "cloudformation"]
published: false
---

## はじめに

iCloudの容量課金を眺めていて、ふと思いました。**写真の保存先くらい、自分のAWSアカウントでよくないか?**

そこで、iPhoneの写真を自分のS3バケットにバックアップするアプリを個人開発しました。ただ作るだけでは面白くないので、次の縛りを入れています。

- **アプリはユーザーのAWSに接続する**(開発者のサーバーは一切ない)
- **利用者にgitやCLIの知識を要求しない**(AWSアカウントとブラウザだけでセットアップ完了)
- **開発マシンにMacを使わない**(ビルドも動作確認もCIで完結)

この記事では、その設計判断とハマりどころを紹介します。

## 全体アーキテクチャ

```
iPhone アプリ (SwiftUI)              ユーザー自身の AWS
┌──────────────┐  ①サインアップ/ログイン   ┌─────────────┐
│               │ ──────────────────▶ │   Cognito    │
│               │ ◀────────────────── │ User Pool    │
│               │   ②ID トークン         └─────────────┘
│               │
│               │  ③POST /presign      ┌─────────────┐
│               │   (Bearer トークン)    │ API Gateway  │
│               │ ──────────────────▶ │ (JWT検証)     │
│               │ ◀────────────────── │   + Lambda   │
│               │   ④署名付き PUT URL    └──────┬──────┘
│               │                             │ 署名
│               │   ⑤PUT(写真バイナリ)   ┌──────▼──────┐
│               │ ──────────────────▶ │      S3      │
└──────────────┘                      └─────────────┘
```

ポイントは、**アプリがAWSの認証情報を一切持たない**ことと、**写真のバイナリがLambdaを経由しない**ことです。

## 設計判断1: presigned URL方式

S3へのアップロードは大きく3つの選択肢があります。

| 方式 | 認証情報の扱い | 評価 |
|---|---|---|
| AWS SDK直接 | Cognito Identity Poolで一時クレデンシャル | アプリが重くなる |
| Amplify | 同上(ラッパー) | 依存が巨大 |
| **presigned URL** | **アプリ側は何も持たない** | **採用** |

presigned URL方式では、Lambdaが「このキーに、このContent-Typeで、1時間以内ならPUTしてよい」という署名付きURLを発行し、アプリはそこに `URLSession` で直接PUTするだけです。SDK依存ゼロで、アップロード経路はS3と直結なので大きなファイルでも高速です。

```python
upload_url = s3.generate_presigned_url(
    "put_object",
    Params={"Bucket": BUCKET_NAME, "Key": key, "ContentType": content_type},
    ExpiresIn=3600,
)
```

## 設計判断2: 認証はCognito + JWTオーソライザー

最初は共有APIキー(`x-api-key`)で作りましたが、「アプリバイナリに埋めた秘密は秘密ではない」ので、早い段階でCognitoに置き換えました。

- API Gateway (HTTP API) の **JWTオーソライザー**がトークンを検証。Lambdaに届く時点で検証済みクレームが手に入る
- S3のキーは `uploads/{sub}/...` とユーザーIDでプレフィックス分離。**他人の領域には構造上書き込めない**
- アプリ側はAmplifyを使わず、CognitoのパブリックAPI(`InitiateAuth` など)を `URLRequest` で直接叩く軽量実装(依存ゼロ)

```yaml
Auth:
  DefaultAuthorizer: CognitoJwtAuthorizer
  Authorizers:
    CognitoJwtAuthorizer:
      JwtConfiguration:
        issuer: !Sub "https://cognito-idp.${AWS::Region}.amazonaws.com/${UserPool}"
        audience:
          - !Ref UserPoolClient
```

トークンはKeychainに `kSecAttrAccessibleAfterFirstUnlock` で保存します。これは後述のバックグラウンドアップロードが**画面ロック中にトークンを更新できるようにするため**で、地味に重要です。

## 設計判断3: 「持ち込みAWS」モデル

このアプリには開発者のサーバーがありません。**各ユーザーが自分のAWSアカウントにバックエンドをデプロイして使います**。ストレージ費用は各自のAWS請求に乗り、開発者はインフラを一切運用しない。個人開発の写真アプリとしては、これが一番誠実な形だと思っています(開発者が飽きてもユーザーの写真は無事)。

問題は「一般ユーザーにどうやってAWS環境を作らせるか」。`git clone` して `sam deploy` — は論外です。答えは**CloudFormationのクイック作成リンク**でした。

```
https://console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks/quickcreate?templateURL=<公開テンプレートのURL>&stackName=photo-uploader
```

このリンクを開くと、AWSコンソールで「スタックの作成」ボタンを押すだけでバックエンド一式(S3 + Cognito + Lambda + API Gateway)が構築されます。テンプレートはLambdaコードを `InlineCode` で埋め込んだ**単一ファイル**にして、ビルド工程そのものを消しました。

デプロイ完了後、Outputsに**アプリ設定用のJSONを1行で出力**しておくのがミソです。

```yaml
Outputs:
  AppConfigJson:
    Value: !Sub '{"apiEndpoint":"https://${Api}.execute-api.${AWS::Region}.amazonaws.com","region":"${AWS::Region}","clientId":"${UserPoolClient}"}'
```

アプリ側は初回起動時に「接続先の設定」画面を出し、このJSONを**QRコードスキャン/ペースト/手動入力**のいずれかで受け取ります(QRはVisionKitの `DataScannerViewController` で、依存ライブラリなし)。接続先はすべて非シークレット(APIはログインで保護されている)ので、配布バイナリは誰の環境情報も含まない汎用品になります。

なお、InlineCode版テンプレートと開発用の `app.py` は二重管理になるため、**CIで両者の一致を検査**しています。ズレたらビルドが落ちる仕掛けです。

## 設計判断4: background URLSessionで「放置できる」バックアップ

写真バックアップは数百枚単位になるので、「アプリを前面に置き続けないと失敗する」では話になりません。転送は `URLSessionConfiguration.background` に委譲しました。

- バックグラウンドセッションは**ファイルからのアップロードのみ**なので、写真データを一時ファイルに書き出してから登録
- タスクごとのメタデータ(アップロードID・ファイルパス・S3キー・リトライ回数)は `taskDescription` にJSONで格納。**アプリがOSに殺されて再起動しても**、デリゲートが発火した時点でメタデータから状態を復元できる
- 署名付きURLはOSの都合で転送が遅延すると失効する(403)ので、**403なら新しいURLを取り直して自動リトライ**(最大3回)。このリトライはアプリ再起動後のデリゲート内でも動く

Swift Concurrencyとの接続は `CheckedContinuation` で行い、UIからは普通の `async` 関数に見えるようにしています。

```swift
func upload(fileURL: URL, contentType: String,
            onProgress: @escaping @Sendable (Double) -> Void) async throws -> String
```

並列度はTaskGroupで4本に制限。1枚ずつの逐次では遅すぎ、無制限ではメモリとネットワークが死にます。

## 重複バックアップの防止

「どの写真をアップロード済みか」をユーザーに管理させたくなかったので、`PhotosPickerItem.itemIdentifier`(フォトライブラリのアセットID)を端末内に記録し、**再選択された写真は自動でスキップ**します。これで「全選択して投げれば、新しい分だけ上がる」という運用が成立します。

ちなみに標準の写真ピッカーはアプリ外プロセスなので、「アップロード済みバッジを出す」「ソートを足す」といったカスタマイズは不可能です。ここは戦わずに、スキップで解決するのが正解でした。

## Macを持たずにiOSアプリを開発する

今回の開発は**終始Macなし**で行いました(実行環境はLinuxコンテナ)。成立させた仕掛けは:

- `.xcodeproj` は**XcodeGen**で生成(`project.yml` だけをコミット)
- GitHub Actionsの**macOSランナー**でビルド+UIテスト
- UIテストがスクリーンショットを撮り、`xcparse` で抽出してArtifact化 → **動く画面をCIの成果物として確認**
- 未署名の `.ipa` もArtifact化し、実機へは**AltStore**でサイドロード(無料Apple IDで7日署名)

「コードを書く → pushする → 10分後にスクショと.ipaが降ってくる」という開発ループです。思ったより快適でした。

## ハマりどころ集

実際に踏んだ罠を供養しておきます。

1. **XcodeGenの新形式 vs 古いXcode**: XcodeGen 2.45+はproject format 77で出力し、Xcode 15.4(macos-14ランナー)では開けない。→ macos-15ランナー(Xcode 16)へ
2. **Formの遅延ロードとXCUITest**: SwiftUIのFormはList背当てで**画面外の行を生成しない**。画面が縦に伸びた瞬間、下の方の要素への `waitForExistence` が偽陰性に。→ 画面上部の要素でアサート
3. **シミュレータのキーボード入力はフレーク**: UIテストの `typeText` がCIで無音で空振りする。→ 起動引数でテスト用設定を注入し、入力自体を排除
4. **全画面広告と閉じかけのシート**: 写真ピッカーが閉じるアニメーション中に全画面広告を `present` すると、UIKitに拒否されて**広告が“ほぼ毎回”出ない**。→ `presentedViewController` が nil になるまで待ってから表示
5. **Windows PowerShell 5.1 三連コンボ**(配布用スクリプトで踏んだ): ①`2>$null` が `ErrorActionPreference=Stop` 下で例外化 ②外部コマンドへ渡す文字列の**内側の引用符が剥がれて**JSONが壊れる ③**BOMなしUTF-8をShift-JISとして誤読**し、日本語コメントの化けたバイトが `}` を食って構文エラー。→ cmd経由のリダイレクト/`file://` でのJSON渡し/BOM付き保存

## 収益化: リワード広告の設計

収益はAdMobで、アップロード開始時に**リワード動画広告**(視聴でアップロード解禁)を挟む設計にしました。バナーより単価が桁違いに高く、「操作1回に1本」という頻度がアプリの使われ方と合っています。

1つだけこだわったのは**フェイルオープン**にしたこと。広告が読み込めないとき(オフライン・在庫なし)は素通しでアップロードを開始します。バックアップという本質機能を広告の都合で人質に取らない — 審査対策でもあり、ユーザーへの誠実さでもあります。

## まとめ

- presigned URL + Cognito JWTで、**認証情報を一切持たないクライアント**が作れる
- CloudFormationクイック作成リンク+設定JSON/QRで、**「自分のAWSを持ち込む」一般向けアプリ**が成立する
- background URLSession + taskDescriptionメタデータ+再署名リトライで、**放置できるバックアップ**が作れる
- XcodeGen + macOSランナー + xcparse + AltStoreで、**Macなしのアプリ開発ループ**が回る

アプリは現在TestFlight公開に向けて準備中です。リリースしたら追記します。

(質問・ツッコミ歓迎です)
