#!/usr/bin/env bash
# 配布者(アプリ所有者)向け: 利用者に配る「クイック作成リンク」を発行します。
# 使い方:  ./publish-template.sh <世界で一意のバケット名> [リージョン]
set -euo pipefail

BUCKET_NAME="${1:?使い方: ./publish-template.sh <バケット名> [リージョン]}"
REGION="${2:-ap-northeast-1}"
KEY="photo-uploader/template.yaml"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# バケットが無ければ作成
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" >/dev/null
    else
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" \
            --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
    fi
    echo "バケット $BUCKET_NAME を作成しました"
fi

# テンプレートのオブジェクトだけ公開読み取りを許可
aws s3api put-public-access-block --bucket "$BUCKET_NAME" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicReadTemplate\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$BUCKET_NAME/$KEY\"}]}"

aws s3 cp "$SCRIPT_DIR/template-quickcreate.yaml" "s3://$BUCKET_NAME/$KEY" >/dev/null

TEMPLATE_URL="https://$BUCKET_NAME.s3.$REGION.amazonaws.com/$KEY"
ENCODED=$(printf '%s' "$TEMPLATE_URL" | sed 's|:|%3A|g; s|/|%2F|g')
LINK="https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks/quickcreate?templateURL=$ENCODED&stackName=photo-uploader"

echo ""
echo "テンプレートを公開しました: $TEMPLATE_URL"
echo ""
echo "─────────── 利用者に配る「クイック作成リンク」 ───────────"
echo "$LINK"
echo "──────────────────────────────────────────────────────"
echo ""
echo "利用者の手順: AWSアカウントでログイン → このリンクを開く → 下部の承認チェックを"
echo "オンにして「スタックの作成」→ 完了後「出力」タブの AppConfigJson をアプリに設定"
