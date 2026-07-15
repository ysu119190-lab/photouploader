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

> **バックアップ経路(単一障害点対策):** 同じテンプレートを GitHub Pages でも配信しています(`docs/template-quickcreate.yaml`)。万一クイック作成リンクの S3 バケットが利用できなくなった場合は、Pages からテンプレートをダウンロードし、AWS コンソールの CloudFormation → スタックの作成 → 「テンプレートファイルのアップロード」で同じバックエンドを構築できます(クイック作成リンクの templateURL に指定できるのは S3 上のファイルのみ、という CloudFormation の制約のため、Pages 版は直接リンクではなくダウンロード用です)。CI が backend 側と docs 側の同期をチェックします。

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
4. 「写真・動画を選択」から複数(枚数無制限)選ぶと、4 並列で S3 へアップロードされ、進捗が表示されます(**動画にも対応**。mp4 / mov / m4v)
5. アップロードが終わると **操作1回ごとの履歴**(日時・件数・成否)が残ります
6. **一度アップロードした写真・動画は自動でスキップ**されるので、同じものを選び直しても二重にバックアップされません
7. 毎回選ぶのが面倒な場合は **「新着をまとめてバックアップ」**(バックアップ画面の一番上)。まだバックアップしていない写真・動画をライブラリから自動で探してアップロードします(初回のみ写真へのアクセス許可が必要)。**アルバム分けも保存先に反映**され、S3上では `albums/<アルバム名>/` フォルダに整理されます
8. **「ライブラリから選ぶ」**を使うと、どれがアップロード済みか(緑のチェック)を見ながら選べます。新しい順/古い順の切り替えと「未アップのみ」フィルタ付き
9. **「カメラで撮ってバックアップ」**で、その場で撮影した写真を直接アップロードできます

> **確認コードのメールが届かない場合:** 迷惑メールフォルダを確認してください(差出人は `no-reply@verificationemail.com`)。なお Cognito の標準メール送信は 1 スタックあたり **1 日 50 通まで**です(個人・家族での利用なら通常問題ありません)。多人数で同じスタックを使う場合は、テンプレートの `CognitoSesSourceArn` パラメータに検証済み SES ID の ARN を渡すと、確認メールが Amazon SES 経由(実質無制限)に切り替わります。

別のAWS環境につなぎ直したい場合は、ログイン画面の「接続先の設定をやり直す」から再設定できます。パスワードを忘れた場合は、ログイン画面の「パスワードを忘れた場合」からメールのリセットコードで再設定できます。

**アカウントの削除:** バックアップタブ左上の「アカウント」→「アカウントを削除」で、ログイン用アカウント(メールアドレス登録)をアプリ内から完全に削除できます(App Store ガイドライン 5.1.1 対応)。S3 にバックアップ済みの写真は削除されず、あなたの AWS 環境に残ります(不要なら AWS コンソールの S3 から削除できます)。

**保存済みの閲覧と復元:** 「保存済み」タブで、アップロード済みの写真・動画を新しい順のグリッドで一覧できます(タップで拡大表示・動画はその場で再生、下に引っ張って更新)。一覧は**アップロード時に自動生成される小さなサムネイル**を読み込むため、表示が速く、通信量も節約モードの取り出し料金もほぼかかりません(フルサイズを読むのは拡大表示のときだけ)。左上の**アルバムメニュー**で、アルバムごとの絞り込みもできます。拡大表示の「端末に保存」ボタンで、**写真アプリへ保存し直す(復元する)**ことができます。機種変更後の書き戻しにも使えます。表示・保存はいずれも S3 への署名付き GET URL 経由で、データがサーバーを経由することはありません。

**保存済みの削除(ゴミ箱方式):** 「保存済み」タブ右上の「選択」から複数選んで削除できます。削除といっても即消えるのではなく、**S3 の `trash/` フォルダに移動して30日後に自動で完全削除**されます(ライフサイクルルール)。間違えて消しても30日以内なら AWS コンソールから書き戻せます。端末内の写真には影響しません。

**保存モード(料金の最適化):** バックアップタブ右上の歯車から「標準」「節約」を選べます。標準は S3 Standard(すぐ表示・保存料高め)、節約は S3 Glacier Instant Retrieval(保存料が約1/5・表示は同じく一瞬・表示ごとに少額の取り出し料金)。バックアップ用途なら節約モードがおすすめです。選択は以降のアップロードに適用され、過去分は変わりません。

**バックグラウンドアップロード対応:** 転送は background `URLSession` 経由なので、ホーム画面に戻る・他のアプリに切り替える・画面をロックしても、送信済みキューに入った分は OS が転送を継続します。署名付き URL が転送待ちの間に失効した場合(HTTP 403)は、新しい URL を取得して自動リトライ(最大 3 回)します。トークンの有効期限が切れていても、Keychain のリフレッシュトークンで自動更新されます。

アップロードが終わると、アプリを離れていた場合は**完了通知**(◯件中◯件アップロード)が届きます。一部が失敗した場合は、進捗一覧の「**失敗した項目を再試行**」で失敗分だけやり直せます。

> **注意:**
> - 写真ライブラリからの読み出し・変換(キュー投入前の準備処理)はアプリが動いている間に行われます。数百枚規模では、キュー投入が終わるまで前面のままが確実です。
> - アプリスイッチャーから上スワイプで強制終了すると、バックグラウンド転送もキャンセルされます。
> - システムによる終了後もアップロード自体は完走します。進捗一覧は再起動後も復元され、転送中だった項目は「中断(完了している場合があります)」と表示されます(実際に届いたかは「保存済み」タブで確認できます)。

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

## 料金の目安

アプリは無料ですが、写真の保存先はあなた自身の AWS なので、**保存量に応じた AWS 利用料(従量課金)**がかかります。

| 保存モード | 写真 100GB あたりの保存料 | 補足 |
|---|---|---|
| 標準(S3 Standard) | 約 375〜400 円/月 | すぐ表示できる。よく見返す人向け |
| 節約(S3 Glacier Instant Retrieval) | 約 75 円/月 | 表示は同じく一瞬。取り出し料金は**拡大表示したときだけ**(一覧は自動生成の小さなサムネイルを使うためほぼ無料) |

- 数 GB 程度なら月数円〜数十円です。アップロード(受信)方向の通信料は無料で、その他(Lambda・API Gateway・Cognito)は個人利用の規模ではほぼ 0 円です
- **やめるとき:** S3 バケットの中身(写真)と CloudFormation スタックを削除すれば請求は止まります。**アプリを削除しただけでは AWS 側の保存料は止まりません**
- 実際の料金は AWS の料金体系・保存量・為替で変動します(2026 年時点・東京リージョンの概算)。正確には [AWS の料金ページ](https://aws.amazon.com/jp/s3/pricing/)を確認してください

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

広告リクエストはすべて **非パーソナライズ(NPA)** で送信します(`AdsConfig.makeRequest()` が `npa=1` を付与)。このため ATT(トラッキング許可ダイアログ)の実装は不要で、App Store の App Privacy も「トラッキングなし」で申告できます(詳細は `notes/app-privacy-label.md`)。パーソナライズ広告に切り替える場合は ATT 対応と申告の変更が必要です。

**本番化の手順(App Store 公開時):**

1. [AdMob](https://admob.google.com/) アカウントを作成し、アプリを登録
2. 発行された**アプリ ID** を `ios/project.yml` の `GADApplicationIdentifier` に設定
3. バナーとリワードの広告ユニットを作成し、それぞれの **広告ユニット ID** を `ios/PhotoUploader/Services/AdsConfig.swift` の `bannerAdUnitID` / `rewardedAdUnitID` に設定
4. `SKAdNetworkItems` に [Google 推奨の SKAdNetwork ID 一覧](https://developers.google.com/admob/ios/quick-start#update_your_infoplist)を追加
5. 広告のパーソナライズを行う場合は ATT(App Tracking Transparency)対応と `NSUserTrackingUsageDescription` の追加を検討

なお、AdMob の収益化は実質的に App Store で公開されたアプリが前提です(AltStore 等のサイドロード配布では審査・収益化ができません)。

## 今後の拡張アイデア

- Sign in with Apple 対応(App Store 配信時に推奨・Apple Developer Program 加入後)
- 運営ホスト版バックエンド(セットアップ不要の共有バックエンド。`notes/hosted-backend-idea.md` 参照)

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
