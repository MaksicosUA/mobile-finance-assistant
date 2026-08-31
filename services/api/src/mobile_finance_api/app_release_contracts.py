"""Strict contract for the app update a device may install (ADR 0026).

Nothing here is financial data. It describes one file: which version it is, how
big, and what it hashes to. The manifest is written by the build tool and read
back strictly, so a malformed one reports "no update" rather than pointing a
device at something unknown.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal, Self

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from .operation_contracts import UtcTimestamp

#: Lowercase hex, as `sha256sum` writes it.
Sha256Digest = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]

#: The four-part Android version name the build resolver produces (ADR 0013).
AndroidVersionName = Annotated[
    str,
    StringConstraints(pattern=r"^[0-9]+(\.[0-9]+){3}$"),
]

#: Bounded so a manifest cannot describe a file the app would try to hold in
#: memory or a device would spend an afternoon fetching.
MAXIMUM_RELEASE_BYTES = 512 * 1024 * 1024


class AppReleaseApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class AppRelease(AppReleaseApiModel):
    version_code: int = Field(alias="versionCode", ge=1)
    version_name: AndroidVersionName = Field(alias="versionName")
    size_bytes: int = Field(alias="sizeBytes", ge=1, le=MAXIMUM_RELEASE_BYTES)
    sha256: Sha256Digest
    # Free text the author writes, shown to a person deciding whether to
    # update. Never user data, and never required.
    notes: (
        Annotated[
            str,
            StringConstraints(strip_whitespace=True, min_length=1, max_length=500),
        ]
        | None
    ) = None
    published_at: UtcTimestamp = Field(alias="publishedAt")

    @model_validator(mode="after")
    def notes_carry_no_control_characters(self) -> Self:
        if self.notes is not None and any(
            ord(character) < 0x20 and character not in "\n\t"
            for character in self.notes
        ):
            raise ValueError("notes contain control characters")
        return self


class AppUpdateResponse(AppReleaseApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    #: Absent when nothing is published, which is a normal answer rather than
    #: an error: a deployment that has never uploaded a build has no update.
    release: AppRelease | None


class AppReleaseErrorDetail(AppReleaseApiModel):
    code: Literal["APP_RELEASE_UNAVAILABLE", "APP_RELEASE_NOT_FOUND"]


class AppReleaseErrorResponse(AppReleaseApiModel):
    detail: AppReleaseErrorDetail


def parse_release_manifest(payload: object) -> AppRelease:
    """Read a manifest written by the build tool, refusing anything unexpected."""

    return AppRelease.model_validate(payload)


def manifest_document(release: AppRelease) -> dict[str, object]:
    """Serialize a manifest for the build tool to write beside the APK."""

    return release.model_dump(mode="json", by_alias=True)


def is_newer(*, release: AppRelease, installed_version_code: int) -> bool:
    """Whether a device on ``installed_version_code`` has something to install.

    Equal is not newer, and older is refused outright: Android would reject the
    downgrade anyway, and reporting an update that cannot install is worse than
    reporting none.
    """

    return release.version_code > installed_version_code


def utc_now() -> datetime:
    from datetime import UTC

    return datetime.now(UTC)
