"""Publishing an update a device can install (ADR 0026).

The server distributes what it was given. It cannot build or sign anything, so
these tests hold the boundary that keeps a bad manifest from pointing a device
at something unknown — and the one that keeps this endpoint from becoming a
public download.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.app_release import (
    APK_FILENAME,
    MANIFEST_FILENAME,
    AppReleaseUnavailable,
    FilesystemAppReleaseStore,
    NoAppReleaseStore,
)
from mobile_finance_api.app_release_contracts import (
    AppRelease,
    is_newer,
    manifest_document,
    parse_release_manifest,
)
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.main import create_app

_PUBLISHED_AT = datetime(2026, 8, 31, 22, 0, tzinfo=UTC)
_USER_ID = "11111111-1111-4111-8111-111111111111"
_APK_BYTES = b"synthetic android package"
_APK_DIGEST = hashlib.sha256(_APK_BYTES).hexdigest()


def _release(**changes: object) -> AppRelease:
    payload: dict[str, object] = {
        "versionCode": 3000140,
        "versionName": "0.1.16.3000140",
        "sizeBytes": len(_APK_BYTES),
        "sha256": _APK_DIGEST,
        "notes": "Повторяющиеся траты",
        "publishedAt": "2026-08-31T22:00:00Z",
    }
    payload.update(changes)
    return AppRelease.model_validate(payload)


@pytest.fixture
def release_directory(tmp_path: Path) -> Iterator[Path]:
    (tmp_path / APK_FILENAME).write_bytes(_APK_BYTES)
    (tmp_path / MANIFEST_FILENAME).write_text(
        json.dumps(manifest_document(_release())),
        encoding="utf-8",
    )
    yield tmp_path


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=_USER_ID, display_name="Synthetic User")


# --- the manifest -------------------------------------------------------------


def test_a_manifest_round_trips() -> None:
    assert parse_release_manifest(manifest_document(_release())) == _release()


def test_a_digest_that_is_not_a_sha256_is_refused() -> None:
    with pytest.raises(ValidationError):
        _release(sha256="not-a-digest")
    with pytest.raises(ValidationError):
        # Uppercase is not what `sha256sum` writes, and two spellings of one
        # digest is one spelling too many.
        _release(sha256=_APK_DIGEST.upper())


def test_an_unknown_key_is_refused_rather_than_ignored() -> None:
    with pytest.raises(ValidationError):
        parse_release_manifest(
            {**manifest_document(_release()), "installSilently": True}
        )


def test_an_absurd_size_is_refused() -> None:
    with pytest.raises(ValidationError):
        _release(sizeBytes=0)
    with pytest.raises(ValidationError):
        _release(sizeBytes=2 * 1024 * 1024 * 1024)


def test_notes_may_be_absent_and_never_carry_control_characters() -> None:
    assert _release(notes=None).notes is None
    with pytest.raises(ValidationError):
        _release(notes="broken\x07bell")


def test_a_malformed_version_name_is_refused() -> None:
    with pytest.raises(ValidationError):
        _release(versionName="0.1.16")


# --- what counts as an update -------------------------------------------------


def test_the_same_version_is_not_an_update() -> None:
    assert is_newer(release=_release(), installed_version_code=3000140) is False


def test_an_older_published_build_is_not_an_update() -> None:
    """Android refuses a downgrade, so offering one would only produce a
    failure the user has to read."""

    assert is_newer(release=_release(), installed_version_code=3000141) is False


def test_a_newer_published_build_is_an_update() -> None:
    assert is_newer(release=_release(), installed_version_code=3000139) is True


# --- the store ----------------------------------------------------------------


def test_no_directory_configured_means_no_update() -> None:
    """A deployment that never published a build is a valid state."""

    assert NoAppReleaseStore().published() is None


def test_an_empty_directory_means_no_update(tmp_path: Path) -> None:
    assert FilesystemAppReleaseStore(directory=tmp_path).published() is None


def test_a_published_release_is_read_with_its_file(release_directory: Path) -> None:
    published = FilesystemAppReleaseStore(directory=release_directory).published()

    assert published is not None
    assert published.release.version_code == 3000140
    assert published.apk_path.read_bytes() == _APK_BYTES


def test_a_manifest_without_its_apk_fails_closed(release_directory: Path) -> None:
    (release_directory / APK_FILENAME).unlink()
    with pytest.raises(AppReleaseUnavailable):
        FilesystemAppReleaseStore(directory=release_directory).published()


def test_a_manifest_that_disagrees_with_the_file_fails_closed(
    release_directory: Path,
) -> None:
    """The manifest is written after the upload, so a size that disagrees means
    the file changed underneath it."""

    (release_directory / APK_FILENAME).write_bytes(_APK_BYTES + b"more")
    with pytest.raises(AppReleaseUnavailable):
        FilesystemAppReleaseStore(directory=release_directory).published()


def test_an_unreadable_manifest_fails_closed(release_directory: Path) -> None:
    # Reporting "up to date" here would hide a misconfiguration forever.
    (release_directory / MANIFEST_FILENAME).write_text("{ not json", encoding="utf-8")
    with pytest.raises(AppReleaseUnavailable):
        FilesystemAppReleaseStore(directory=release_directory).published()


# --- over HTTP ----------------------------------------------------------------


def _application(store: object | None = None):  # type: ignore[no-untyped-def]
    return create_app(
        current_user_authenticator=_StaticAuthenticator(),
        app_release_store=store,  # type: ignore[arg-type]
    )


async def _get(app: object, path: str, *, authenticated: bool = True):  # type: ignore[no-untyped-def]
    headers = {"Authorization": "Bearer synthetic"} if authenticated else {}
    async with AsyncClient(
        transport=ASGITransport(app=app),  # type: ignore[arg-type]
        base_url="http://test",
    ) as client:
        return await client.get(path, headers=headers)


def test_an_anonymous_caller_gets_neither_the_manifest_nor_the_file() -> None:
    """The hostname is public through Certificate Transparency (ADR 0024), so
    an open endpoint here would be a download link for anyone who looked."""

    async def scenario() -> None:
        app = create_app()
        for path in ("/api/v1/app/update", "/api/v1/app/download"):
            response = await _get(app, path, authenticated=False)
            assert response.status_code == 401, path

    asyncio.run(scenario())


def test_a_deployment_without_a_release_reports_no_update() -> None:
    async def scenario() -> None:
        response = await _get(_application(), "/api/v1/app/update")

        assert response.status_code == 200
        assert response.json() == {"schemaVersion": "1", "release": None}
        assert response.headers["cache-control"] == "no-store"

    asyncio.run(scenario())


def test_a_published_release_is_reported(release_directory: Path) -> None:
    async def scenario() -> None:
        store = FilesystemAppReleaseStore(directory=release_directory)
        response = await _get(_application(store), "/api/v1/app/update")

        assert response.status_code == 200
        release = response.json()["release"]
        assert release["versionCode"] == 3000140
        assert release["sha256"] == _APK_DIGEST

    asyncio.run(scenario())


def test_a_broken_release_answers_503_rather_than_up_to_date(
    release_directory: Path,
) -> None:
    async def scenario() -> None:
        (release_directory / APK_FILENAME).unlink()
        store = FilesystemAppReleaseStore(directory=release_directory)
        response = await _get(_application(store), "/api/v1/app/update")

        assert response.status_code == 503
        assert response.json()["detail"]["code"] == "APP_RELEASE_UNAVAILABLE"

    asyncio.run(scenario())


def test_the_download_serves_the_package(release_directory: Path) -> None:
    async def scenario() -> None:
        store = FilesystemAppReleaseStore(directory=release_directory)
        response = await _get(_application(store), "/api/v1/app/download")

        assert response.status_code == 200
        assert response.content == _APK_BYTES
        assert (
            response.headers["content-type"]
            == "application/vnd.android.package-archive"
        )

    asyncio.run(scenario())


def test_downloading_nothing_is_a_typed_404() -> None:
    async def scenario() -> None:
        response = await _get(_application(), "/api/v1/app/download")

        assert response.status_code == 404
        assert response.json()["detail"]["code"] == "APP_RELEASE_NOT_FOUND"

    asyncio.run(scenario())


def test_the_manifest_never_carries_financial_data(release_directory: Path) -> None:
    """A contract test, not a style note: this endpoint answers before a user
    has any data, and it must never grow a field that describes them."""

    async def scenario() -> None:
        store = FilesystemAppReleaseStore(directory=release_directory)
        response = await _get(_application(store), "/api/v1/app/update")
        keys = set(response.json()["release"])

        assert keys == {
            "versionCode",
            "versionName",
            "sizeBytes",
            "sha256",
            "notes",
            "publishedAt",
        }

    asyncio.run(scenario())
