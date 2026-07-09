"""Lambda handling the app's API. Two routes, both JWT-protected:

POST /presign  — issue a presigned S3 PUT URL for uploading one photo
GET  /photos   — list the caller's uploaded photos with presigned GET URLs

The API Gateway JWT authorizer (Cognito) has already validated the caller's
ID token before this handler runs; the verified claims arrive in the request
context. Photo bytes never pass through Lambda — uploads PUT directly to S3
and views GET directly from S3 via presigned URLs. Each user's photos live
under their own uploads/<user id>/ prefix.
"""

import datetime
import json
import os
import uuid

import boto3
from botocore.config import Config

s3 = boto3.client("s3", config=Config(signature_version="s3v4"))

BUCKET_NAME = os.environ["BUCKET_NAME"]
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

# S3 storage classes the app may request. STANDARD is the default (frequent
# viewing); GLACIER_IR (Glacier Instant Retrieval) is much cheaper to store
# and still retrieves instantly, suited to seldom-viewed backups.
ALLOWED_STORAGE_CLASSES = {"STANDARD", "GLACIER_IR"}


def handler(event, _context):
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
    )
    user_id = claims.get("sub")
    if not user_id:
        return _response(401, {"message": "Unauthorized"})

    if event.get("routeKey") == "GET /photos":
        return _list_photos(user_id, event)
    return _presign(user_id, event)


def _presign(user_id, event):
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

    storage_class = body.get("storageClass", "STANDARD")
    if storage_class not in ALLOWED_STORAGE_CLASSES:
        return _response(
            400,
            {
                "message": "Unsupported storageClass",
                "allowed": sorted(ALLOWED_STORAGE_CLASSES),
            },
        )

    now = datetime.datetime.now(datetime.timezone.utc)
    key = f"uploads/{user_id}/{now:%Y/%m/%d}/{uuid.uuid4()}{extension}"

    params = {"Bucket": BUCKET_NAME, "Key": key, "ContentType": content_type}
    # STANDARD is S3's default; only sign a StorageClass when it differs, so
    # the client only needs the x-amz-storage-class header for GLACIER_IR.
    if storage_class != "STANDARD":
        params["StorageClass"] = storage_class

    upload_url = s3.generate_presigned_url(
        "put_object",
        Params=params,
        ExpiresIn=EXPIRES_IN_SECONDS,
    )

    return _response(
        200,
        {
            "uploadUrl": upload_url,
            "key": key,
            "expiresIn": EXPIRES_IN_SECONDS,
            "storageClass": storage_class,
        },
    )


def _list_photos(user_id, event):
    params = event.get("queryStringParameters") or {}
    try:
        offset = max(int(params.get("offset", "0")), 0)
        limit = min(max(int(params.get("limit", "40")), 1), 100)
    except ValueError:
        return _response(400, {"message": "offset and limit must be integers"})

    # Object keys embed the upload date (uploads/<sub>/YYYY/MM/DD/<uuid>),
    # so a reverse key sort yields newest-first without extra metadata.
    prefix = f"uploads/{user_id}/"
    objects = []
    kwargs = {"Bucket": BUCKET_NAME, "Prefix": prefix}
    while True:
        page = s3.list_objects_v2(**kwargs)
        objects.extend(
            {
                "key": item["Key"],
                "size": item["Size"],
                "lastModified": item["LastModified"].isoformat(),
            }
            for item in page.get("Contents", [])
        )
        token = page.get("NextContinuationToken")
        if not token:
            break
        kwargs["ContinuationToken"] = token

    objects.sort(key=lambda item: item["key"], reverse=True)
    selected = objects[offset : offset + limit]
    # Signing is local computation — no AWS calls — so per-item URLs are cheap.
    for item in selected:
        item["url"] = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": BUCKET_NAME, "Key": item["key"]},
            ExpiresIn=EXPIRES_IN_SECONDS,
        )

    next_offset = offset + limit if offset + limit < len(objects) else None
    return _response(
        200,
        {"photos": selected, "total": len(objects), "nextOffset": next_offset},
    )


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
