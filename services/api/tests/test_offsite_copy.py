"""The copy of a dump that leaves the host (`infra/docker/offsite.py`).

The script runs on the host with the system Python, outside this package, so it
is loaded from its file. The storage here is a small HTTP server on loopback
that speaks the three calls the script makes, and `age` is a stand-in: what is
under test is what the script sends, refuses and remembers, not the cipher.
"""

from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import os
import stat
import sys
import threading
import time
from collections.abc import Iterator
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

_SCRIPT = Path(__file__).resolve().parents[3] / "infra" / "docker" / "offsite.py"

_KEY_ID = "synthetic-key-id"
_KEY = "synthetic-application-key-do-not-print"
_BUCKET = "synthetic-backups"
_RECIPIENT = "age1syntheticrecipientsyntheticrecipientsyntheticrecipientsynth"
_ACCOUNT_TOKEN = "synthetic-account-token"
_UPLOAD_TOKEN = "synthetic-upload-token"
_DUMP = b"PGDMP synthetic dump, in the clear " * 40


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("mfa_offsite", _SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


offsite = _load()


class _Storage:
    """What a Backblaze B2 bucket does with the three calls, and a record."""

    def __init__(self) -> None:
        self.capabilities = ["writeFiles"]
        self.buckets: list[dict[str, str]] | None = [
            {"id": "bucket-id-1", "name": _BUCKET}
        ]
        self.authorize_status = 200
        #: Statuses to answer the next uploads with before accepting one.
        self.upload_failures: list[int] = []
        self.uploads: list[dict[str, Any]] = []
        self.upload_urls_issued = 0
        #: Answer as if something other than what was sent had been stored.
        self.stores_something_else = False
        #: Hand out an upload address that is not TLS.
        self.sends_uploads_in_the_clear = False
        self.seen_authorization: list[str] = []
        self.base = ""

    def handle(self, handler: BaseHTTPRequestHandler) -> tuple[int, dict[str, Any]]:
        path = handler.path
        authorization = handler.headers.get("Authorization", "")
        self.seen_authorization.append(authorization)
        if path.endswith("/b2_authorize_account"):
            expected = "Basic " + base64.b64encode(f"{_KEY_ID}:{_KEY}".encode()).decode(
                "ascii"
            )
            if self.authorize_status != 200 or authorization != expected:
                return 401, {"code": "bad_auth_token", "message": "no"}
            return 200, {
                "accountId": "synthetic",
                "authorizationToken": _ACCOUNT_TOKEN,
                "apiInfo": {
                    "storageApi": {
                        "apiUrl": self.base,
                        "allowed": {
                            "buckets": self.buckets,
                            "capabilities": self.capabilities,
                            "namePrefix": None,
                        },
                    }
                },
            }
        if "/b2_get_upload_url" in path:
            if authorization != _ACCOUNT_TOKEN or "bucketId=bucket-id-1" not in path:
                return 401, {"code": "unauthorized", "message": "no"}
            self.upload_urls_issued += 1
            return 200, {
                "bucketId": "bucket-id-1",
                "uploadUrl": (
                    "http://storage.example.com/upload/1"
                    if self.sends_uploads_in_the_clear
                    else f"{self.base}/upload/{self.upload_urls_issued}"
                ),
                "authorizationToken": _UPLOAD_TOKEN,
            }
        if path.startswith("/upload/"):
            length = int(handler.headers.get("Content-Length", "0"))
            body = handler.rfile.read(length)
            if self.upload_failures:
                return self.upload_failures.pop(0), {"code": "service_unavailable"}
            if authorization != _UPLOAD_TOKEN:
                return 401, {"code": "bad_auth_token"}
            claimed = handler.headers.get("X-Bz-Content-Sha1", "")
            if hashlib.sha1(body).hexdigest() != claimed:  # noqa: S324
                return 400, {"code": "bad_request"}
            self.uploads.append(
                {
                    "name": handler.headers.get("X-Bz-File-Name", ""),
                    "body": body,
                    "sha1": claimed,
                }
            )
            return 200, {
                "fileId": f"file-{len(self.uploads)}",
                "fileName": handler.headers.get("X-Bz-File-Name", ""),
                "contentSha1": "0" * 40 if self.stores_something_else else claimed,
                "action": "upload",
            }
        return 404, {"code": "not_found"}


@pytest.fixture
def storage() -> Iterator[_Storage]:
    record = _Storage()

    class Handler(BaseHTTPRequestHandler):
        def _answer(self) -> None:
            status, body = record.handle(self)
            payload = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        do_GET = _answer  # noqa: N815 - the name http.server looks for
        do_POST = _answer  # noqa: N815

        def log_message(self, *arguments: Any) -> None:
            del arguments

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    record.base = f"http://127.0.0.1:{server.server_address[1]}"
    thread = threading.Thread(
        target=server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True
    )
    thread.start()
    try:
        yield record
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def _stand_in_age(directory: Path, *, body: str) -> Path:
    tool = directory / "age-stand-in"
    tool.write_text(f"#!{sys.executable}\n{body}\n", encoding="utf-8")
    tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
    return tool


#: Writes an age header and the input reversed: recognisably not the input.
_SEALS = """
import sys
arguments = sys.argv[1:]
assert arguments[0] == "--encrypt", arguments
recipient = arguments[arguments.index("--recipient") + 1]
target = arguments[arguments.index("--output") + 1]
source = arguments[-1]
with open(source, "rb") as handle:
    plain = handle.read()
with open(target, "wb") as handle:
    handle.write(b"age-encryption.org/v1\\n-> X25519 " + recipient.encode() + b"\\n")
    handle.write(plain[::-1])
"""

#: Fails the way a tool does when it cannot run at all.
_REFUSES = "import sys\nsys.exit(1)"

#: Exits cleanly having copied the dump across unsealed.
_COPIES = """
import shutil, sys
arguments = sys.argv[1:]
shutil.copyfile(arguments[-1], arguments[arguments.index("--output") + 1])
"""


def _environment(storage: _Storage, age: Path) -> dict[str, str]:
    return {
        "MFA_OFFSITE_AGE_RECIPIENT": _RECIPIENT,
        "MFA_OFFSITE_B2_KEY_ID": _KEY_ID,
        "MFA_OFFSITE_B2_APPLICATION_KEY": _KEY,
        "MFA_OFFSITE_B2_BUCKET": _BUCKET,
        "MFA_OFFSITE_AGE": str(age),
        "MFA_OFFSITE_B2_AUTHORIZE_URL": storage.base + "/b2api/v4/b2_authorize_account",
    }


def _dump(directory: Path, stamp: str, *, age_hours: float = 0.1) -> Path:
    path = directory / f"mfa-{stamp}.dump"
    path.write_bytes(_DUMP + stamp.encode())
    moment = time.time() - age_hours * 3600
    os.utime(path, (moment, moment))
    return path


@pytest.fixture
def backups(tmp_path: Path) -> Path:
    directory = tmp_path / "backups"
    directory.mkdir()
    return directory


@pytest.fixture
def age(tmp_path: Path) -> Path:
    return _stand_in_age(tmp_path, body=_SEALS)


# --- what leaves ---------------------------------------------------------------


def test_a_new_dump_leaves_sealed_under_its_own_name(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    dump = _dump(backups, "2026-11-17T033000Z")

    status = offsite.run([str(backups)], _environment(storage, age))

    assert status == 0
    assert [upload["name"] for upload in storage.uploads] == [
        "mfa-2026-11-17T033000Z.dump.age"
    ]
    sent = storage.uploads[0]["body"]
    assert sent.startswith(b"age-encryption.org/v1\n")
    # The dump itself is nowhere in what was sent.
    assert _DUMP[:64] not in sent
    assert "sent mfa-2026-11-17T033000Z.dump.age" in capsys.readouterr().out
    # The local dump is untouched and no ciphertext is left beside it.
    assert dump.read_bytes().startswith(_DUMP)
    assert sorted(path.name for path in backups.iterdir()) == [
        "mfa-2026-11-17T033000Z.dump",
        "mfa-2026-11-17T033000Z.dump.sent",
    ]


def test_it_is_sealed_to_the_configured_public_key(
    storage: _Storage, backups: Path, age: Path
) -> None:
    _dump(backups, "2026-11-17T033000Z")

    offsite.run([str(backups)], _environment(storage, age))

    assert _RECIPIENT.encode() in storage.uploads[0]["body"]


def test_what_was_sent_is_remembered_and_not_sent_twice(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    dump = _dump(backups, "2026-11-17T033000Z")
    environment = _environment(storage, age)

    assert offsite.run([str(backups)], environment) == 0
    assert offsite.run([str(backups)], environment) == 0

    assert len(storage.uploads) == 1
    receipt = json.loads(offsite.marker(dump).read_text())
    assert receipt["fileId"] == "file-1"
    assert receipt["sha1"] == storage.uploads[0]["sha1"]
    assert stat.S_IMODE(offsite.marker(dump).stat().st_mode) == 0o600
    assert "nothing is waiting" in capsys.readouterr().out


def test_last_nights_failed_copy_goes_with_tonights(
    storage: _Storage, backups: Path, age: Path
) -> None:
    _dump(backups, "2026-11-16T033000Z", age_hours=24.2)
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], _environment(storage, age)) == 0

    assert [upload["name"] for upload in storage.uploads] == [
        "mfa-2026-11-16T033000Z.dump.age",
        "mfa-2026-11-17T033000Z.dump.age",
    ]


def test_an_old_unsent_dump_stays_home_and_is_counted(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    """Sent late it would outlive the fourteen days an erased account is
    promised: the storage counts from the day a copy arrived (ADR 0030)."""

    old = _dump(backups, "2026-11-10T033000Z", age_hours=7 * 24)
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], _environment(storage, age)) == 0

    assert [upload["name"] for upload in storage.uploads] == [
        "mfa-2026-11-17T033000Z.dump.age"
    ]
    assert not offsite.marker(old).exists()
    assert "1 older dump(s) were never sent" in capsys.readouterr().out


def test_only_dumps_are_sent(storage: _Storage, backups: Path, age: Path) -> None:
    _dump(backups, "2026-11-17T033000Z")
    (backups / "mfa-2026-11-17T040000Z.dump.partial").write_bytes(b"half a dump")
    (backups / "notes.txt").write_text("not a dump")

    assert offsite.run([str(backups)], _environment(storage, age)) == 0

    assert len(storage.uploads) == 1


# --- what is refused -----------------------------------------------------------


def test_nothing_set_up_is_said_plainly_and_is_not_a_failure(
    backups: Path, capsys: Any
) -> None:
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], {}) == 0

    assert "not set up" in capsys.readouterr().out


def test_half_set_up_is_a_mistake(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    environment = _environment(storage, age)
    del environment["MFA_OFFSITE_B2_APPLICATION_KEY"]
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], environment) == offsite.EXIT_MISCONFIGURED

    assert "MFA_OFFSITE_B2_APPLICATION_KEY" in capsys.readouterr().err
    assert storage.uploads == []


@pytest.mark.parametrize(
    "recipient",
    [
        "AGE-SECRET-KEY-1SYNTHETICSYNTHETICSYNTHETICSYNTHETICSYNTHETICSYNTHETIC",
        "not-a-key",
    ],
)
def test_a_secret_key_is_never_accepted_where_the_public_one_goes(
    storage: _Storage, backups: Path, age: Path, recipient: str, capsys: Any
) -> None:
    environment = _environment(storage, age)
    environment["MFA_OFFSITE_AGE_RECIPIENT"] = recipient
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], environment) == offsite.EXIT_MISCONFIGURED

    captured = capsys.readouterr()
    assert recipient not in captured.out + captured.err
    assert storage.uploads == []


def test_a_dump_that_was_not_sealed_is_not_sent(
    storage: _Storage, backups: Path, tmp_path: Path
) -> None:
    dump = _dump(backups, "2026-11-17T033000Z")
    careless = _stand_in_age(tmp_path, body=_COPIES)

    status = offsite.run([str(backups)], _environment(storage, careless))

    assert status == offsite.EXIT_FAILED
    assert storage.uploads == []
    assert not offsite.marker(dump).exists()
    assert sorted(path.name for path in backups.iterdir()) == [dump.name]


def test_a_tool_that_fails_sends_nothing(
    storage: _Storage, backups: Path, tmp_path: Path, capsys: Any
) -> None:
    dump = _dump(backups, "2026-11-17T033000Z")
    broken = _stand_in_age(tmp_path, body=_REFUSES)

    assert offsite.run([str(backups)], _environment(storage, broken)) == 1

    assert storage.uploads == []
    assert not offsite.marker(dump).exists()
    assert "could not send" in capsys.readouterr().err


def test_a_missing_tool_names_what_to_install(
    storage: _Storage, backups: Path, tmp_path: Path, capsys: Any
) -> None:
    _dump(backups, "2026-11-17T033000Z")
    environment = _environment(storage, tmp_path / "no-such-age")

    assert offsite.run([str(backups)], environment) == offsite.EXIT_MISCONFIGURED

    assert "apt install age" in capsys.readouterr().err


def test_a_key_for_another_bucket_is_refused(
    storage: _Storage, backups: Path, age: Path
) -> None:
    storage.buckets = [{"id": "bucket-id-9", "name": "someone-elses"}]
    _dump(backups, "2026-11-17T033000Z")

    status = offsite.run([str(backups)], _environment(storage, age))

    assert status == offsite.EXIT_MISCONFIGURED
    assert storage.uploads == []


def test_a_key_for_the_whole_account_is_refused(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    storage.buckets = None
    _dump(backups, "2026-11-17T033000Z")

    status = offsite.run([str(backups)], _environment(storage, age))

    assert status == offsite.EXIT_MISCONFIGURED
    assert "limited to the backup bucket" in capsys.readouterr().err
    assert storage.uploads == []


def test_a_key_that_cannot_write_is_refused(
    storage: _Storage, backups: Path, age: Path
) -> None:
    storage.capabilities = ["listFiles", "readFiles"]
    _dump(backups, "2026-11-17T033000Z")

    status = offsite.run([str(backups)], _environment(storage, age))

    assert status == offsite.EXIT_MISCONFIGURED
    assert storage.uploads == []


def test_a_wrong_storage_key_fails_without_touching_the_dumps(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    storage.authorize_status = 401
    dump = _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], _environment(storage, age)) == 1

    assert "refused to sign in: 401 bad_auth_token" in capsys.readouterr().err
    assert not offsite.marker(dump).exists()


def test_an_address_that_is_not_tls_is_refused(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    environment = _environment(storage, age)
    environment["MFA_OFFSITE_B2_AUTHORIZE_URL"] = "http://storage.example.com/authorize"
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], environment) == 1

    # Refused for what it is, before anything was sent to it.
    assert "not HTTPS" in capsys.readouterr().err
    assert storage.seen_authorization == []


def test_a_storage_that_asks_for_the_copy_in_the_clear_does_not_get_it(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    storage.sends_uploads_in_the_clear = True
    dump = _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], _environment(storage, age)) == 1

    assert "not HTTPS" in capsys.readouterr().err
    assert storage.uploads == []
    assert not offsite.marker(dump).exists()


# --- when the storage stumbles -------------------------------------------------


def test_a_refused_upload_address_is_replaced_once(
    storage: _Storage, backups: Path, age: Path
) -> None:
    storage.upload_failures = [503]
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], _environment(storage, age)) == 0

    assert storage.upload_urls_issued == 2
    assert len(storage.uploads) == 1


def test_a_storage_that_keeps_refusing_is_a_failure_to_try_again_tomorrow(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    storage.upload_failures = [503, 503]
    dump = _dump(backups, "2026-11-17T033000Z")
    environment = _environment(storage, age)

    assert offsite.run([str(backups)], environment) == 1
    assert "could not send mfa-2026-11-17T033000Z.dump: 503" in capsys.readouterr().err
    assert not offsite.marker(dump).exists()
    assert sorted(path.name for path in backups.iterdir()) == [dump.name]

    # The next run finds it still waiting.
    assert offsite.run([str(backups)], environment) == 0
    assert len(storage.uploads) == 1


def test_one_failed_dump_does_not_hold_back_the_next(
    storage: _Storage, backups: Path, age: Path
) -> None:
    storage.upload_failures = [503, 503]
    first = _dump(backups, "2026-11-16T033000Z", age_hours=24.2)
    second = _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], _environment(storage, age)) == 1

    assert not offsite.marker(first).exists()
    assert offsite.marker(second).exists()


def test_a_stored_file_that_is_not_what_was_sent_is_not_counted_as_sent(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    storage.stores_something_else = True
    dump = _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], _environment(storage, age)) == 1

    assert not offsite.marker(dump).exists()
    assert "checksum is not the one sent" in capsys.readouterr().err


# --- what is said --------------------------------------------------------------


def test_no_key_or_token_is_ever_printed(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    storage.upload_failures = [503, 503]
    _dump(backups, "2026-11-17T033000Z")
    environment = _environment(storage, age)

    offsite.run([str(backups)], environment)
    offsite.run(["--check", str(backups)], environment)
    offsite.run([str(backups)], environment)

    captured = capsys.readouterr()
    said = captured.out + captured.err
    for secret in (_KEY, _KEY_ID, _ACCOUNT_TOKEN, _UPLOAD_TOKEN, "/upload/"):
        assert secret not in said, secret


def test_a_check_says_what_the_key_may_do_and_sends_nothing(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run(["--check", str(backups)], _environment(storage, age)) == 0

    assert "may: writeFiles" in capsys.readouterr().out
    assert storage.uploads == []


def test_a_key_that_can_also_delete_is_pointed_out(
    storage: _Storage, backups: Path, age: Path, capsys: Any
) -> None:
    storage.capabilities = ["deleteFiles", "listBuckets", "readFiles", "writeFiles"]
    _dump(backups, "2026-11-17T033000Z")

    assert offsite.run([str(backups)], _environment(storage, age)) == 0

    said = capsys.readouterr().out
    assert "may do more than add files (deleteFiles, readFiles)" in said
    assert len(storage.uploads) == 1


def test_a_check_with_nothing_set_up_is_not_a_pass(backups: Path) -> None:
    assert offsite.run(["--check", str(backups)], {}) == offsite.EXIT_MISCONFIGURED
