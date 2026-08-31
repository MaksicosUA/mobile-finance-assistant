"""Where a published Android build lives, and how it is read (ADR 0026).

The server distributes what it was given. It cannot build or sign anything, so
a compromised host can serve an old APK or none — it cannot forge one, because
the device's package installer refuses whatever is not signed with the key that
signed the installed app.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from .app_release_contracts import AppRelease, parse_release_manifest

#: Fixed names. Nothing in a request ever reaches the filesystem, so there is
#: no path to traverse.
MANIFEST_FILENAME = "latest.json"
APK_FILENAME = "latest.apk"


class AppReleaseUnavailable(Exception):
    """A release directory was configured but could not be read or trusted."""


@dataclass(frozen=True, slots=True)
class PublishedRelease:
    release: AppRelease
    apk_path: Path


class AppReleaseStore(Protocol):
    def published(self) -> PublishedRelease | None:
        """Return what is published, or None when nothing is."""


class NoAppReleaseStore:
    """No release directory configured.

    A deployment that has never published a build genuinely has no update, so
    this is a quiet answer rather than an error.
    """

    def published(self) -> PublishedRelease | None:
        return None


class FilesystemAppReleaseStore:
    """Reads a manifest and the APK beside it.

    Fails closed once a directory is configured: a manifest that cannot be read,
    disagrees with the file, or describes a different size is a
    misconfiguration someone intended to work, and reporting "up to date" would
    hide it forever.
    """

    def __init__(self, *, directory: Path) -> None:
        self._directory = directory

    def published(self) -> PublishedRelease | None:
        manifest_path = self._directory / MANIFEST_FILENAME
        apk_path = self._directory / APK_FILENAME
        if not manifest_path.exists():
            return None
        try:
            payload = json.loads(manifest_path.read_text(encoding="utf-8"))
            release = parse_release_manifest(payload)
        except (OSError, ValueError) as error:
            raise AppReleaseUnavailable from error
        if not apk_path.is_file():
            raise AppReleaseUnavailable
        # The manifest is written after the upload, so a size that disagrees
        # means the file changed underneath it rather than a race.
        if apk_path.stat().st_size != release.size_bytes:
            raise AppReleaseUnavailable
        return PublishedRelease(release=release, apk_path=apk_path)
