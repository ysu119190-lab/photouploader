"""Lambda handler that issues presigned S3 PUT URLs for photo uploads.

The iOS app POSTs {"contentType": "image/jpeg"} with an "x-api-key" header,
and receives {"uploadUrl": ..., "key": ..., "expiresIn": ...}. It then PUTs
the photo bytes directly to S3 using that URL, so the app never needs AWS
credentials and the photo bytes never pass through Lambda.
"""

import datetime
import json
import os
import uuid

import boto3
from botocore.config import Config

s3 = boto3.client("s3", config=Config(signature_version="s3v4"))

BUCKET_NAME = os.environ["BUCKET_NAME"]
API_KEY = os.environ.get("API_KEY", "")
# Background uploads may sit in the OS queue for a while before they run,
# so give the URL a generous lifetime. The app retries with a fresh URL on
# 403 in case it still expires (URLs signed with Lambda's temporary
# credentials die with those credentials regardless of this value).
EXPIRES_IN_SECONDS = 3600

# Content types the app may upload, mapped to the object key extension.
ALLOWED_CONTENT_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/heic": ".heic",
    "image/heif": ".heif",
    "image/webp": ".webp",
    "image/gif": ".gif",
}


def handler(event, _context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if not API_KEY or headers.get("x-api-key") != API_KEY:
        return _response(403, {"message": "Forbidden"})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"message": "Request body must be valid JSON"})

    content_type = body.get("contentType", "")
    extension = ALLOWED_CONTENT_TYPES.get(content_type)
    if extension is None:
        return _response(
            400,
            {
                "message": "Unsupported contentType",
                "allowed": sorted(ALLOWED_CONTENT_TYPES),
            },
        )

    now = datetime.datetime.now(datetime.timezone.utc)
    key = f"uploads/{now:%Y/%m/%d}/{uuid.uuid4()}{extension}"

    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": BUCKET_NAME, "Key": key, "ContentType": content_type},
        ExpiresIn=EXPIRES_IN_SECONDS,
    )

    return _response(
        200,
        {"uploadUrl": upload_url, "key": key, "expiresIn": EXPIRES_IN_SECONDS},
    )


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
