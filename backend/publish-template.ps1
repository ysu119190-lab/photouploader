# 配布者(アプリ所有者)向け: 利用者に配る「クイック作成リンク」を発行します。
# テンプレートを自分のS3バケットに公開アップロードし、リンクを表示します。
#
# 使い方 (PowerShell):
#   .\publish-template.ps1 -BucketName <世界で一意のバケット名> [-Region ap-northeast-1]
#
# 例:
#   .\publish-template.ps1 -BucketName photouploader-template-yourname
param(
    [Parameter(Mandatory = $true)][string]$BucketName,
    [string]$Region = "ap-northeast-1"
)
$Key = "photo-uploader/template.yaml"

function Assert-LastExit([string]$Message) {
    if ($LASTEXITCODE -ne 0) {
        Write-Host $Message -ForegroundColor Red
        exit 1
    }
}

# バケットが無ければ作成(存在確認はcmd経由でエラー出力ごと捨てる:
# Windows PowerShell 5.1 は 2>$null でのstderrリダイレクトを例外扱いするため)
cmd /c "aws s3api head-bucket --bucket $BucketName >nul 2>&1"
if ($LASTEXITCODE -ne 0) {
    if ($Region -eq "us-east-1") {
        aws s3api create-bucket --bucket $BucketName --region $Region | Out-Null
    } else {
        aws s3api create-bucket --bucket $BucketName --region $Region `
            --create-bucket-configuration LocationConstraint=$Region | Out-Null
    }
    Assert-LastExit "バケットを作成できませんでした。バケット名が世界で一意か(既に他人に使われていないか)確認してください。"
    Write-Host "バケット $BucketName を作成しました"
}

# テンプレートのオブジェクトだけ公開読み取りを許可
aws s3api put-public-access-block --bucket $BucketName --public-access-block-configuration `
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false | Out-Null
Assert-LastExit "パブリックアクセス設定を変更できませんでした。"

$policy = "{`"Version`":`"2012-10-17`",`"Statement`":[{`"Sid`":`"PublicReadTemplate`",`"Effect`":`"Allow`",`"Principal`":`"*`",`"Action`":`"s3:GetObject`",`"Resource`":`"arn:aws:s3:::$BucketName/$Key`"}]}"
aws s3api put-bucket-policy --bucket $BucketName --policy $policy | Out-Null
Assert-LastExit "バケットポリシーを設定できませんでした。"

# テンプレートをアップロード
aws s3 cp (Join-Path $PSScriptRoot "template-quickcreate.yaml") "s3://$BucketName/$Key" | Out-Null
Assert-LastExit "テンプレートをアップロードできませんでした。"

$templateUrl = "https://$BucketName.s3.$Region.amazonaws.com/$Key"
$encoded = [uri]::EscapeDataString($templateUrl)
$link = "https://console.aws.amazon.com/cloudformation/home?region=$Region#/stacks/quickcreate?templateURL=$encoded&stackName=photo-uploader"

Write-Host ""
Write-Host "テンプレートを公開しました: $templateUrl"
Write-Host ""
Write-Host "─────────── 利用者に配る「クイック作成リンク」 ───────────" -ForegroundColor Yellow
Write-Host $link -ForegroundColor Cyan
Write-Host "──────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host ""
Write-Host "利用者の手順: AWSアカウントでログイン → このリンクを開く → 下部の承認チェックを"
Write-Host "オンにして「スタックの作成」→ 完了後「出力」タブの AppConfigJson をアプリに設定"
