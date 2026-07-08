#!/usr/bin/env bash
# デプロイ済みバックエンドの接続設定を表示し、QRコード付きHTMLを生成します。
# 使い方:  ./show-config.sh [スタック名]   (省略時: photo-uploader)
set -euo pipefail

STACK_NAME="${1:-photo-uploader}"

JSON=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='AppConfigJson'].OutputValue" --output text)

if [ -z "$JSON" ] || [ "$JSON" = "None" ]; then
    echo "設定を取得できませんでした。スタック名 ($STACK_NAME) と AWS CLI の設定を確認してください。" >&2
    exit 1
fi

echo ""
echo "アプリの「まとめて貼り付け」欄には、次の【ここから】と【ここまで】の間の1行を"
echo "丸ごと(波かっこ { } も含めて)コピーして貼り付けてください。"
echo ""
echo "─────────────── ここから ───────────────"
echo "$JSON"
echo "─────────────── ここまで ───────────────"
echo ""

HTML_PATH="$(pwd)/app-config-qr.html"
cat > "$HTML_PATH" <<EOF
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
<code>$JSON</code>
<script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
<script>
  var qr = qrcode(0, 'M');
  qr.addData('$JSON');
  qr.make();
  document.getElementById('qr').innerHTML = qr.createImgTag(6, 8);
</script>
</body>
</html>
EOF

echo "QRコードを生成しました: $HTML_PATH"
if command -v open >/dev/null 2>&1; then
    open "$HTML_PATH"
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$HTML_PATH"
fi
