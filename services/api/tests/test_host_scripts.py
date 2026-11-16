"""The two scripts a timer runs on the host: `watch.sh` and `backup.sh`.

They are run for real, with the commands they call replaced by stand-ins on
`PATH`. What is under test is the part that is theirs: which failures are
named, what the watcher is told, and what a failed run leaves behind.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import time
from pathlib import Path

import pytest

_INFRA = Path(__file__).resolve().parents[3] / "infra" / "docker"
_WATCH_PING = "https://watcher.example.test/ping/synthetic-watch-capability"
_BACKUP_PING = "https://watcher.example.test/ping/synthetic-backup-capability"

pytestmark = pytest.mark.skipif(
    shutil.which("bash") is None, reason="the host scripts are bash"
)

#: Logs every call and answers by what was asked for.
_CURL = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$STUB_LOG"
for argument in "$@"; do address="$argument"; done
case "$address" in
  */api/v1/health) exit "${STUB_HEALTH_EXIT:-0}" ;;
  *) exit "${STUB_PING_EXIT:-0}" ;;
esac
"""

#: `docker compose ... exec -T projector ...` and `... exec -T postgres pg_dump`.
_DOCKER = """#!/usr/bin/env bash
printf 'docker %s\\n' "$*" >> "$STUB_LOG"
case "$*" in
  *pg_dump*)
    [ "${STUB_DUMP_EXIT:-0}" -eq 0 ] || exit "$STUB_DUMP_EXIT"
    head -c "${STUB_DUMP_BYTES:-4096}" /dev/zero | tr '\\0' 'd'
    ;;
  *--check-health*)
    echo "Home projector health status=${STUB_PROJECTOR_STATUS:-healthy}"
    exit "${STUB_PROJECTOR_EXIT:-0}"
    ;;
esac
"""

_DF = """#!/usr/bin/env bash
echo "Use%"
echo " ${STUB_DISK_PERCENT:-40}%"
"""

#: `s_client` prints nothing useful; `x509 -checkend` is the verdict.
_OPENSSL = """#!/usr/bin/env bash
case "$1" in
  x509) exit "${STUB_CERTIFICATE_EXIT:-0}" ;;
  *) cat > /dev/null; exit 0 ;;
esac
"""


class _Host:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.bin = root / "bin"
        self.bin.mkdir()
        self.data = root / "data"
        self.data.mkdir()
        self.log = root / "calls.log"
        self.log.write_text("")
        self.env_file = root / "host.env"
        for name, body in (
            ("curl", _CURL),
            ("docker", _DOCKER),
            ("df", _DF),
            ("openssl", _OPENSSL),
        ):
            tool = self.bin / name
            tool.write_text(body)
            tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
        self.write_env()

    def write_env(self, **extra: str) -> None:
        settings = {
            "MFA_DOMAIN": "finance.example.test",
            "MFA_DATA_ROOT": str(self.data),
            "POSTGRES_USER": "synthetic",
            "POSTGRES_DB": "synthetic",
            **extra,
        }
        self.env_file.write_text(
            "".join(f"{name}={value}\n" for name, value in settings.items())
        )

    def run(self, script: str, **stubs: str) -> subprocess.CompletedProcess[str]:
        environment = {
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "MFA_ENV_FILE": str(self.env_file),
            "STUB_LOG": str(self.log),
            "MFA_BACKUP_MINIMUM_BYTES": "1000",
            **stubs,
        }
        return subprocess.run(  # noqa: S603 - the repository's own script
            ["bash", str(_INFRA / script)],  # noqa: S607
            env=environment,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines()

    def pings(self) -> list[str]:
        return [line for line in self.calls() if "watcher.example.test" in line]

    @property
    def backups(self) -> Path:
        return self.data / "backups"


@pytest.fixture
def host(tmp_path: Path) -> _Host:
    return _Host(tmp_path)


# --- watch.sh ------------------------------------------------------------------


def test_a_well_host_says_so_to_the_watcher(host: _Host) -> None:
    host.write_env(MFA_WATCH_PING_URL=_WATCH_PING)

    result = host.run("watch.sh")

    assert result.returncode == 0, result.stderr
    pings = host.pings()
    assert len(pings) == 1
    assert pings[0].endswith(_WATCH_PING)
    assert "--data-raw ok" in pings[0]


def test_the_service_is_asked_the_way_a_phone_reaches_it(host: _Host) -> None:
    host.run("watch.sh")

    assert any(
        line.endswith("https://finance.example.test/api/v1/health")
        for line in host.calls()
    )


@pytest.mark.parametrize(
    ("stub", "value", "word"),
    [
        ("STUB_HEALTH_EXIT", "22", "api"),
        ("STUB_PROJECTOR_EXIT", "1", "projector"),
        ("STUB_DISK_PERCENT", "93", "disk"),
        ("STUB_CERTIFICATE_EXIT", "1", "certificate"),
    ],
)
def test_each_failure_is_named_and_reported_at_once(
    host: _Host, stub: str, value: str, word: str
) -> None:
    host.write_env(MFA_WATCH_PING_URL=_WATCH_PING)

    result = host.run("watch.sh", **{stub: value})

    assert result.returncode == 1
    assert f"failing: {word}" in result.stderr
    pings = host.pings()
    assert len(pings) == 1
    assert pings[0].endswith(_WATCH_PING + "/fail")
    assert f"--data-raw {word}" in pings[0]


def test_one_failure_does_not_stop_the_other_questions(host: _Host) -> None:
    host.write_env(MFA_WATCH_PING_URL=_WATCH_PING)

    result = host.run(
        "watch.sh",
        STUB_HEALTH_EXIT="7",
        STUB_PROJECTOR_EXIT="1",
        STUB_DISK_PERCENT="99",
        STUB_CERTIFICATE_EXIT="1",
    )

    assert result.returncode == 1
    assert "failing: api projector disk certificate" in result.stderr
    assert "--data-raw api projector disk certificate" in host.pings()[0]


def test_a_disk_just_under_the_line_is_well(host: _Host) -> None:
    assert host.run("watch.sh", STUB_DISK_PERCENT="89").returncode == 0
    assert host.run("watch.sh", STUB_DISK_PERCENT="90").returncode == 1


def test_what_the_projector_said_is_kept_only_when_it_failed(host: _Host) -> None:
    well = host.run("watch.sh")
    assert "Home projector health" not in well.stdout + well.stderr

    unwell = host.run(
        "watch.sh", STUB_PROJECTOR_EXIT="1", STUB_PROJECTOR_STATUS="stalled"
    )
    assert "status=stalled" in unwell.stderr


def test_without_a_watcher_the_answer_is_only_the_exit_status(host: _Host) -> None:
    assert host.run("watch.sh").returncode == 0
    assert host.run("watch.sh", STUB_HEALTH_EXIT="22").returncode == 1
    assert host.pings() == []


def test_a_watcher_that_cannot_be_reached_changes_no_answer(host: _Host) -> None:
    host.write_env(MFA_WATCH_PING_URL=_WATCH_PING)

    well = host.run("watch.sh", STUB_PING_EXIT="6")
    unwell = host.run("watch.sh", STUB_PING_EXIT="6", STUB_HEALTH_EXIT="22")

    assert well.returncode == 0
    assert "could not be told" in well.stderr
    assert unwell.returncode == 1


def test_the_watchers_address_is_never_printed(host: _Host) -> None:
    host.write_env(MFA_WATCH_PING_URL=_WATCH_PING)

    result = host.run("watch.sh", STUB_PING_EXIT="6", STUB_HEALTH_EXIT="22")

    assert "synthetic-watch-capability" not in result.stdout + result.stderr


def test_a_host_with_no_settings_refuses_to_guess(host: _Host) -> None:
    host.env_file.unlink()

    assert host.run("watch.sh").returncode == 78


# --- backup.sh -----------------------------------------------------------------


def _aged(path: Path, days: float) -> Path:
    moment = time.time() - days * 86400
    os.utime(path, (moment, moment))
    return path


def test_a_good_dump_is_kept_and_reported(host: _Host) -> None:
    host.write_env(MFA_BACKUP_PING_URL=_BACKUP_PING)

    result = host.run("backup.sh")

    assert result.returncode == 0, result.stderr
    dumps = sorted(host.backups.glob("mfa-*.dump"))
    assert len(dumps) == 1
    assert stat.S_IMODE(dumps[0].stat().st_mode) == 0o600
    assert stat.S_IMODE(host.backups.stat().st_mode) == 0o700
    assert list(host.backups.glob("*.partial")) == []
    # Nothing is set up to leave the host, and the run says so in as many words.
    assert "not set up" in result.stdout
    pings = host.pings()
    assert len(pings) == 1
    assert pings[0].endswith(_BACKUP_PING)
    assert "--data-raw ok" in pings[0]


def test_a_dump_that_failed_leaves_nothing_and_says_which_step(host: _Host) -> None:
    host.write_env(MFA_BACKUP_PING_URL=_BACKUP_PING)

    result = host.run("backup.sh", STUB_DUMP_EXIT="1")

    assert result.returncode != 0
    assert list(host.backups.iterdir()) == []
    pings = host.pings()
    assert len(pings) == 1
    assert pings[0].endswith(_BACKUP_PING + "/fail")
    assert "--data-raw dump" in pings[0]


def test_a_dump_too_small_to_be_one_is_refused(host: _Host) -> None:
    host.write_env(MFA_BACKUP_PING_URL=_BACKUP_PING)

    result = host.run("backup.sh", STUB_DUMP_BYTES="10")

    assert result.returncode == 1
    assert list(host.backups.iterdir()) == []
    assert host.pings()[0].endswith("/fail")


def test_a_dump_is_gone_at_the_run_fourteen_days_after_its_own(host: _Host) -> None:
    """Not fifteen: an erased account is promised fourteen (ADR 0030)."""

    host.backups.mkdir(mode=0o700)
    # Taken a few minutes later in the night than tonight's run.
    due = host.backups / "mfa-old.dump"
    due.write_bytes(b"x")
    _aged(due, 14 - 0.004)
    receipt = host.backups / "mfa-old.dump.sent"
    receipt.write_text("{}")
    _aged(receipt, 14 - 0.004)
    kept = host.backups / "mfa-kept.dump"
    kept.write_bytes(b"x")
    _aged(kept, 13)
    stale = host.backups / "mfa-dead.dump.partial"
    stale.write_bytes(b"x")
    _aged(stale, 2)

    result = host.run("backup.sh")

    assert result.returncode == 0, result.stderr
    names = {path.name for path in host.backups.iterdir()}
    assert "mfa-old.dump" not in names
    assert "mfa-old.dump.sent" not in names
    assert "mfa-dead.dump.partial" not in names
    assert "mfa-kept.dump" in names


def test_a_failed_dump_ages_nothing_out(host: _Host) -> None:
    host.backups.mkdir(mode=0o700)
    last_good = host.backups / "mfa-old.dump"
    last_good.write_bytes(b"x")
    _aged(last_good, 30)

    result = host.run("backup.sh", STUB_DUMP_EXIT="1")

    assert result.returncode != 0
    assert last_good.exists()


def test_a_copy_that_could_not_leave_fails_the_run_and_keeps_the_dump(
    host: _Host,
) -> None:
    # Set up, and pointed at a storage that is not there.
    host.write_env(
        MFA_BACKUP_PING_URL=_BACKUP_PING,
        MFA_OFFSITE_AGE_RECIPIENT="age1syntheticrecipientsyntheticrecipient",
        MFA_OFFSITE_B2_KEY_ID="synthetic-key-id",
        MFA_OFFSITE_B2_APPLICATION_KEY="synthetic-application-key",
        MFA_OFFSITE_B2_BUCKET="synthetic-backups",
        MFA_OFFSITE_B2_AUTHORIZE_URL="http://127.0.0.1:9/b2api/v4/b2_authorize_account",
    )

    result = host.run("backup.sh")

    assert result.returncode == 1
    assert len(list(host.backups.glob("mfa-*.dump"))) == 1
    assert list(host.backups.glob("*.sent")) == []
    pings = host.pings()
    assert len(pings) == 1
    assert pings[0].endswith(_BACKUP_PING + "/fail")
    assert "--data-raw offsite" in pings[0]
    assert "synthetic-application-key" not in result.stdout + result.stderr


def test_the_backup_watchers_address_is_never_printed(host: _Host) -> None:
    host.write_env(MFA_BACKUP_PING_URL=_BACKUP_PING)

    result = host.run("backup.sh", STUB_PING_EXIT="6")

    assert result.returncode == 0
    assert "could not be told" in result.stderr
    assert "synthetic-backup-capability" not in result.stdout + result.stderr
