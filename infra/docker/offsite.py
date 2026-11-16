#!/usr/bin/env python3
"""Send the dumps that have not left this host yet to Backblaze B2, encrypted.

    offsite.py DIRECTORY           encrypt and upload what is waiting
    offsite.py --check DIRECTORY   say what the key may do; send nothing

The dumps sit on the same volume as the database, so a lost volume, a lost
host, or a lost provider account takes them along. A copy has to leave.

What leaves is ciphertext. `age` encrypts each dump to a public key, and this
host holds only that public key: it can seal a dump and cannot open one. The
private half stays with the owner, off every machine this one can reach, so
whoever takes the storage account, or this host, still reads nothing.

The storage key should be able to add and nothing else. A host that has been
taken over then cannot remove the copies made before it was.

Standard library only, and Python 3.10: it runs on the host, beside
`backup.sh`, not in a container.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

AUTHORIZE_URL = "https://api.backblazeb2.com/b2api/v4/b2_authorize_account"

#: How far back an unsent dump is still sent. Two nights: a failed upload is
#: tried again the next night and the one after. Not further, because the
#: storage ages a copy out by the day it arrived, and a dump sent late would
#: outlive the fourteen days an erased account is promised (ADR 0030).
CATCH_UP_SECONDS = 2 * 24 * 60 * 60

#: How every age file begins, binary or armored. Checked before anything is
#: sent, so a tool that failed quietly cannot pass a plain dump along.
AGE_HEADER = b"age-encryption.org/v1\n"

#: Exit statuses. 78 is sysexits' EX_CONFIG, as `backup.sh` uses it.
EXIT_FAILED = 1
EXIT_MISCONFIGURED = 78

_SETTINGS = (
    "MFA_OFFSITE_AGE_RECIPIENT",
    "MFA_OFFSITE_B2_KEY_ID",
    "MFA_OFFSITE_B2_APPLICATION_KEY",
    "MFA_OFFSITE_B2_BUCKET",
)


class Misconfigured(Exception):
    """The settings cannot be used as they are. Nothing was sent."""


class StorageRefused(Exception):
    """The storage did not take the request. Safe to print: it holds a status
    and the storage's own error code, never a key or a token."""


@dataclass(frozen=True)
class Settings:
    recipient: str
    key_id: str
    application_key: str
    bucket: str
    age: str
    authorize_url: str


@dataclass(frozen=True)
class Storage:
    api_url: str
    token: str
    bucket_id: str
    capabilities: tuple


def load_settings(environment: Mapping[str, str]) -> Settings | None:
    """None when off-site copies are not set up at all; an error when they are
    half set up, which is a mistake rather than a choice."""

    values = {name: environment.get(name, "").strip() for name in _SETTINGS}
    present = [name for name, value in values.items() if value]
    if not present:
        return None
    missing = [name for name in _SETTINGS if name not in present]
    if missing:
        raise Misconfigured("set all of them or none: missing " + ", ".join(missing))
    recipient = values["MFA_OFFSITE_AGE_RECIPIENT"]
    # A private key here would be a secret on the one machine that must not
    # hold it. Refused loudly rather than used.
    if not recipient.startswith("age1") or "SECRET" in recipient.upper():
        raise Misconfigured(
            "MFA_OFFSITE_AGE_RECIPIENT must be a public key (age1...), "
            "never the secret one"
        )
    return Settings(
        recipient=recipient,
        key_id=values["MFA_OFFSITE_B2_KEY_ID"],
        application_key=values["MFA_OFFSITE_B2_APPLICATION_KEY"],
        bucket=values["MFA_OFFSITE_B2_BUCKET"],
        age=environment.get("MFA_OFFSITE_AGE", "").strip() or "age",
        authorize_url=environment.get("MFA_OFFSITE_B2_AUTHORIZE_URL", "").strip()
        or AUTHORIZE_URL,
    )


def _require_safe(url: str) -> None:
    """A dump's ciphertext and the storage key travel over TLS or not at all.

    Plain HTTP is accepted only to this machine itself, which is what a test
    stands a storage up on.
    """

    parts = urllib.parse.urlsplit(url)
    if parts.scheme == "https":
        return
    if parts.scheme == "http" and parts.hostname in ("127.0.0.1", "localhost"):
        return
    raise StorageRefused("an address that is not HTTPS")


def _request(
    url: str,
    *,
    headers: Mapping[str, str],
    data: bytes | None = None,
    timeout: float = 60.0,
) -> dict:
    _require_safe(url)
    request = urllib.request.Request(  # noqa: S310 - the scheme is checked above
        url,
        data=data,
        headers=dict(headers),
        method="POST" if data is not None else "GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        code = ""
        try:
            code = str(json.loads(error.read().decode("utf-8")).get("code", ""))
        except (ValueError, AttributeError, UnicodeDecodeError):
            pass
        # The status and the storage's own word for it. Not the URL, which for
        # an upload is a capability, and never a header.
        raise StorageRefused(f"{error.code} {code}".strip()) from None
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise StorageRefused(f"unreachable ({type(error).__name__})") from None
    except ValueError:
        raise StorageRefused("an answer that is not JSON") from None


def authorize(settings: Settings) -> Storage:
    secret = f"{settings.key_id}:{settings.application_key}".encode()
    answer = _request(
        settings.authorize_url,
        headers={"Authorization": "Basic " + base64.b64encode(secret).decode("ascii")},
    )
    try:
        storage = answer["apiInfo"]["storageApi"]
        allowed = storage["allowed"]
        capabilities = tuple(sorted(str(item) for item in allowed["capabilities"]))
        buckets = allowed.get("buckets") or []
        api_url = str(storage["apiUrl"])
        token = str(answer["authorizationToken"])
    except (KeyError, TypeError):
        raise StorageRefused("an authorization answer of an unknown shape") from None
    if "writeFiles" not in capabilities:
        raise Misconfigured("this storage key cannot write files")
    # A key for the whole account names no bucket. It is refused: this host
    # should hold a key to its own bucket and no other.
    if not buckets:
        raise Misconfigured("the storage key must be limited to the backup bucket")
    for bucket in buckets:
        if isinstance(bucket, dict) and bucket.get("name") == settings.bucket:
            return Storage(
                api_url=api_url.rstrip("/"),
                token=token,
                bucket_id=str(bucket["id"]),
                capabilities=capabilities,
            )
    raise Misconfigured("the storage key does not reach MFA_OFFSITE_B2_BUCKET")


def beyond_adding(storage: Storage) -> list:
    """What the key may do that a key for adding copies has no need of."""

    return [
        capability
        for capability in storage.capabilities
        if capability.startswith(("delete", "read", "share", "bypass"))
        or capability in ("writeBuckets", "writeKeys", "writeFileRetentions")
    ]


def _upload_once(storage: Storage, source: Path, name: str, sha1: str) -> dict:
    target = _request(
        storage.api_url
        + "/b2api/v4/b2_get_upload_url?"
        + urllib.parse.urlencode({"bucketId": storage.bucket_id}),
        headers={"Authorization": storage.token},
    )
    try:
        upload_url = str(target["uploadUrl"])
        upload_token = str(target["authorizationToken"])
    except (KeyError, TypeError):
        raise StorageRefused("an upload address of an unknown shape") from None
    return _request(
        upload_url,
        data=source.read_bytes(),
        headers={
            "Authorization": upload_token,
            "X-Bz-File-Name": urllib.parse.quote(name, safe="/"),
            "Content-Type": "application/octet-stream",
            # The storage checks what arrived against this and refuses a
            # mismatch, so what is stored is what was sealed here.
            "X-Bz-Content-Sha1": sha1,
        },
        timeout=300.0,
    )


def upload(storage: Storage, source: Path, name: str) -> dict:
    sha1 = hashlib.sha1(source.read_bytes()).hexdigest()  # noqa: S324 - the storage's checksum
    try:
        answer = _upload_once(storage, source, name, sha1)
    except StorageRefused:
        # An upload address is good until it refuses one; the storage asks for
        # a fresh one and a second try. Once, not a loop.
        answer = _upload_once(storage, source, name, sha1)
    if answer.get("contentSha1") not in (sha1, "unverified:" + sha1):
        raise StorageRefused("a stored file whose checksum is not the one sent")
    return {"fileId": str(answer.get("fileId", "")), "sha1": sha1}


def encrypt(settings: Settings, source: Path, target: Path) -> None:
    try:
        completed = subprocess.run(  # noqa: S603 - the operator's own tool
            [
                settings.age,
                "--encrypt",
                "--recipient",
                settings.recipient,
                "--output",
                str(target),
                str(source),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError:
        raise Misconfigured(
            f"`{settings.age}` is not installed (apt install age)"
        ) from None
    if completed.returncode != 0:
        raise StorageRefused("age could not encrypt the dump")
    # Whatever went wrong, the plain dump is never what gets sent in its place:
    # only a file that opens the way an age file does goes any further.
    with target.open("rb") as sealed:
        if sealed.read(len(AGE_HEADER)) != AGE_HEADER:
            raise StorageRefused("age produced something that is not an age file")


def marker(dump: Path) -> Path:
    return dump.with_name(dump.name + ".sent")


def waiting(directory: Path, now: float) -> tuple:
    """(dumps to send, oldest first; how many unsent ones are too old to send)."""

    recent = []
    stale = 0
    for dump in sorted(directory.glob("mfa-*.dump")):
        if marker(dump).exists():
            continue
        if now - dump.stat().st_mtime > CATCH_UP_SECONDS:
            stale += 1
        else:
            recent.append(dump)
    return recent, stale


def send(settings: Settings, storage: Storage, dump: Path) -> int:
    sealed = dump.with_name(dump.name + ".age.partial")
    # Left by a run that was killed; age is not asked to write over it.
    sealed.unlink(missing_ok=True)
    try:
        encrypt(settings, dump, sealed)
        size = sealed.stat().st_size
        receipt = upload(storage, sealed, dump.name + ".age")
    finally:
        # Ciphertext is not kept here: the dump beside it is the local copy.
        sealed.unlink(missing_ok=True)
    receipt["sentAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    record = marker(dump)
    record.write_text(json.dumps(receipt) + "\n", encoding="utf-8")
    os.chmod(record, 0o600)
    return size


def run(arguments: Sequence[str], environment: Mapping[str, str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("directory", type=Path)
    parser.add_argument("--check", action="store_true")
    options = parser.parse_args(arguments)

    try:
        settings = load_settings(environment)
        if settings is None:
            print("off-site copies are not set up: every dump stays on this host only")
            return EXIT_MISCONFIGURED if options.check else 0
        storage = authorize(settings)
    except Misconfigured as error:
        print(f"off-site copies are misconfigured: {error}", file=sys.stderr)
        return EXIT_MISCONFIGURED
    except StorageRefused as error:
        print(f"the storage refused to sign in: {error}", file=sys.stderr)
        return EXIT_FAILED

    extra = beyond_adding(storage)
    if extra:
        print(
            "note: the storage key may do more than add files ("
            + ", ".join(extra)
            + "); only Object Lock on the bucket keeps a copy from whoever holds it"
        )
    if options.check:
        print(
            "the storage key reaches the bucket and may: "
            + ", ".join(storage.capabilities)
        )
        return 0

    dumps, stale = waiting(options.directory, time.time())
    if stale:
        print(f"{stale} older dump(s) were never sent and stay on this host only")
    failed = 0
    for dump in dumps:
        try:
            size = send(settings, storage, dump)
        except Misconfigured as error:
            print(f"off-site copies are misconfigured: {error}", file=sys.stderr)
            return EXIT_MISCONFIGURED
        except (StorageRefused, OSError) as error:
            reason = (
                error if isinstance(error, StorageRefused) else type(error).__name__
            )
            print(f"could not send {dump.name}: {reason}", file=sys.stderr)
            failed += 1
            continue
        print(f"sent {dump.name}.age ({size} bytes)")
    if failed:
        return EXIT_FAILED
    if not dumps:
        print("nothing is waiting to be sent")
    return 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:], os.environ))
