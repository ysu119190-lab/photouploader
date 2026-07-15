"""Unit tests for the API Lambda (backend/src/presign/app.py).

S3 is replaced with a small fake so the tests run offline; the point is the
key layout, ownership validation, sorting, and request validation logic.
Run with: pytest backend/tests -q
"""

import datetime
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src", "presign"))
os.environ.setdefault("BUCKET_NAME", "test-bucket")

import app  # noqa: E402

USER = "user-sub-1234"


class FakeS3:
    """Just enough of the S3 client for the handler's code paths."""

    def __init__(self, objects=None):
        # key -> {"Size": int, "LastModified": datetime}
        self.objects = dict(objects or {})
        self.copied = []
        self.deleted = []
        self.fail_keys = set()

    def generate_presigned_url(self, operation, Params, ExpiresIn):
        return f"https://signed.example/{operation}/{Params['Key']}"

    def list_objects_v2(self, Bucket, Prefix, **kwargs):
        contents = [
            {"Key": key, "Size": meta["Size"], "LastModified": meta["LastModified"]}
            for key, meta in sorted(self.objects.items())
            if key.startswith(Prefix)
        ]
        return {"Contents": contents}

    def copy_object(self, Bucket, CopySource, Key, **kwargs):
        if CopySource["Key"] in self.fail_keys:
            raise RuntimeError("copy failed")
        self.copied.append((CopySource["Key"], Key))

    def delete_object(self, Bucket, Key):
        self.deleted.append(Key)


def make_event(route, body=None, query=None):
    return {
        "routeKey": route,
        "body": json.dumps(body) if body is not None else None,
        "queryStringParameters": query,
        "requestContext": {"authorizer": {"jwt": {"claims": {"sub": USER}}}},
    }


def call(route, body=None, query=None):
    response = app.handler(make_event(route, body, query), None)
    return response["statusCode"], json.loads(response["body"])


@pytest.fixture(autouse=True)
def fake_s3(monkeypatch):
    fake = FakeS3()
    monkeypatch.setattr(app, "s3", fake)
    return fake


# --- helpers ---------------------------------------------------------------

def test_sanitize_album_strips_separators_and_caps_length():
    assert app._sanitize_album("家族/旅行\\2026") == "家族旅行2026"
    assert app._sanitize_album("  My   Album  ") == "My Album"
    assert app._sanitize_album("") is None
    assert app._sanitize_album(None) is None
    assert app._sanitize_album(123) is None
    assert app._sanitize_album("あ" * 100) == "あ" * app.MAX_ALBUM_LENGTH


def test_thumb_key_swaps_prefix_and_extension():
    assert (
        app._thumb_key(f"uploads/{USER}/2026/07/15/abc.heic")
        == f"thumbs/{USER}/2026/07/15/abc.jpg"
    )
    assert (
        app._thumb_key(f"uploads/{USER}/albums/旅行/2026/07/15/abc.mov")
        == f"thumbs/{USER}/albums/旅行/2026/07/15/abc.jpg"
    )


# --- POST /presign ---------------------------------------------------------

def test_presign_returns_dated_key_under_user_prefix():
    status, body = call("POST /presign", {"contentType": "image/jpeg"})
    assert status == 200
    assert body["key"].startswith(f"uploads/{USER}/")
    assert body["key"].endswith(".jpg")
    assert body["storageClass"] == "STANDARD"
    assert "thumbnailUploadUrl" not in body


def test_presign_embeds_sanitized_album_in_key():
    status, body = call(
        "POST /presign",
        {"contentType": "video/mp4", "album": " 家族/旅行 "},
    )
    assert status == 200
    assert body["key"].startswith(f"uploads/{USER}/albums/家族旅行/")
    assert body["key"].endswith(".mp4")


def test_presign_with_thumbnail_returns_matching_thumb_urls():
    status, body = call(
        "POST /presign", {"contentType": "image/png", "thumbnail": True}
    )
    assert status == 200
    assert body["thumbnailKey"] == app._thumb_key(body["key"])
    assert body["thumbnailUploadUrl"].endswith(body["thumbnailKey"])


def test_presign_rejects_unknown_content_type_and_storage_class():
    status, body = call("POST /presign", {"contentType": "application/zip"})
    assert status == 400
    status, body = call(
        "POST /presign",
        {"contentType": "image/jpeg", "storageClass": "DEEP_ARCHIVE"},
    )
    assert status == 400


def test_presign_thumbnail_for_rejects_foreign_keys():
    status, _ = call("POST /presign", {"thumbnailFor": "uploads/other-user/x.jpg"})
    assert status == 403
    status, body = call(
        "POST /presign", {"thumbnailFor": f"uploads/{USER}/2026/07/15/a.jpg"}
    )
    assert status == 200
    assert body["thumbnailKey"] == f"thumbs/{USER}/2026/07/15/a.jpg"


# --- GET /photos -----------------------------------------------------------

def _seed_listing(fake_s3):
    when = datetime.datetime(2026, 7, 1, tzinfo=datetime.timezone.utc)
    entries = {
        f"uploads/{USER}/2026/07/01/old.jpg": 0,
        f"uploads/{USER}/albums/旅行/2026/07/03/newest.jpg": 2,
        f"uploads/{USER}/2026/07/02/mid.mp4": 1,
        "uploads/other-user/2026/07/04/foreign.jpg": 3,
    }
    for key, day_offset in entries.items():
        fake_s3.objects[key] = {
            "Size": 100,
            "LastModified": when + datetime.timedelta(days=day_offset),
        }
    # A thumbnail exists for the newest item only.
    fake_s3.objects[f"thumbs/{USER}/albums/旅行/2026/07/03/newest.jpg"] = {
        "Size": 10,
        "LastModified": when,
    }


def test_list_photos_sorts_newest_first_and_maps_thumbnails(fake_s3):
    _seed_listing(fake_s3)
    status, body = call("GET /photos")
    assert status == 200
    keys = [item["key"] for item in body["photos"]]
    assert keys == [
        f"uploads/{USER}/albums/旅行/2026/07/03/newest.jpg",
        f"uploads/{USER}/2026/07/02/mid.mp4",
        f"uploads/{USER}/2026/07/01/old.jpg",
    ]
    assert body["albums"] == ["旅行"]
    assert "thumbnailUrl" in body["photos"][0]
    assert "thumbnailUrl" not in body["photos"][1]
    assert body["total"] == 3
    assert body["nextOffset"] is None


def test_list_photos_album_filter_keeps_full_album_list(fake_s3):
    _seed_listing(fake_s3)
    status, body = call("GET /photos", query={"album": "旅行"})
    assert status == 200
    assert body["total"] == 1
    assert body["photos"][0]["key"].startswith(f"uploads/{USER}/albums/旅行/")
    assert body["albums"] == ["旅行"]


def test_list_photos_pagination(fake_s3):
    _seed_listing(fake_s3)
    status, body = call("GET /photos", query={"offset": "0", "limit": "2"})
    assert status == 200
    assert len(body["photos"]) == 2
    assert body["nextOffset"] == 2


# --- POST /photos/delete ---------------------------------------------------

def test_delete_moves_to_trash_and_drops_thumbnail(fake_s3):
    key = f"uploads/{USER}/2026/07/01/a.jpg"
    status, body = call("POST /photos/delete", {"keys": [key]})
    assert status == 200
    assert body["deleted"] == [key]
    assert (key, f"trash/{USER}/2026/07/01/a.jpg") in fake_s3.copied
    assert key in fake_s3.deleted
    assert f"thumbs/{USER}/2026/07/01/a.jpg" in fake_s3.deleted


def test_delete_rejects_foreign_and_malformed_keys(fake_s3):
    status, body = call(
        "POST /photos/delete",
        {"keys": ["uploads/other-user/x.jpg", 42]},
    )
    assert status == 200
    assert body["deleted"] == []
    assert len(body["errors"]) == 2
    assert fake_s3.copied == []


def test_delete_validates_body(fake_s3):
    assert call("POST /photos/delete", {"keys": []})[0] == 400
    assert call("POST /photos/delete", {})[0] == 400
    assert call("POST /photos/delete", {"keys": ["k"] * 101})[0] == 400


def test_delete_isolates_per_key_failures(fake_s3):
    ok = f"uploads/{USER}/2026/07/01/ok.jpg"
    bad = f"uploads/{USER}/2026/07/01/bad.jpg"
    fake_s3.fail_keys.add(bad)
    status, body = call("POST /photos/delete", {"keys": [bad, ok]})
    assert status == 200
    assert body["deleted"] == [ok]
    assert body["errors"][0]["key"] == bad


def test_unauthorized_without_sub():
    event = make_event("GET /photos")
    event["requestContext"] = {}
    response = app.handler(event, None)
    assert response["statusCode"] == 401
