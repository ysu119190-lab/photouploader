# デプロイ済みバックエンドの接続設定を表示し、QRコード付きHTMLを生成します。
# 使い方 (PowerShell):  .\show-config.ps1 [スタック名]
#   スタック名を省略すると photo-uploader を使います。
param([string]$StackName = "photo-uploader")

$json = aws cloudformation describe-stacks --stack-name $StackName `
    --query "Stacks[0].Outputs[?OutputKey=='AppConfigJson'].OutputValue" --output text

if ($LASTEXITCODE -ne 0 -or -not $json) {
    Write-Error "設定を取得できませんでした。スタック名 ($StackName) と AWS CLI の設定を確認してください。"
    exit 1
}

Write-Host ""
Write-Host "アプリの「まとめて貼り付け」欄には、次の【ここから】と【ここまで】の間の1行を" -ForegroundColor Yellow
Write-Host "丸ごと(波かっこ { } も含めて)コピーして貼り付けてください。" -ForegroundColor Yellow
Write-Host ""
Write-Host "─────────────── ここから ───────────────" -ForegroundColor Cyan
Write-Host $json
Write-Host "─────────────── ここまで ───────────────" -ForegroundColor Cyan
Write-Host ""

# QRコード付きHTMLを生成してブラウザで開く(アプリの「QRコードを読み取る」でスキャンできます)
$htmlPath = Join-Path (Get-Location) "app-config-qr.html"
$html = @"
<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<title>PhotoUploader 接続設定QR</title>
<style>
  body { font-family: sans-serif; text-align: center; padding: 32px; }
  #qr { margin: 24px auto; }
  code { display: inline-block; margin-top: 16px; padding: 10px; background: #f2f2f7;
         border-radius: 8px; word-break: break-all; max-width: 520px; font-size: 12px; }
</style>
</head>
<body>
<h2>PhotoUploader 接続設定</h2>
<p>iPhoneアプリの「QRコードを読み取る」でこのQRをスキャンしてください</p>
<div id="qr">(QRコードの表示にはインターネット接続が必要です)</div>
<code>$json</code>
<script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
<script>
  var qr = qrcode(0, 'M');
  qr.addData('$json');
  qr.make();
  document.getElementById('qr').innerHTML = qr.createImgTag(6, 8);
</script>
</body>
</html>
"@
Set-Content -Path $htmlPath -Value $html -Encoding UTF8
Write-Host "QRコードを生成しました: $htmlPath (ブラウザで開きます)"
Start-Process $htmlPath
