#!/usr/bin/env python3
"""Print a signed, expiring link that delivers the published build (ADR 0026).

The update path behind the bearer token cannot deliver a *first* install: the
token comes from the app. This prints the other door — a capability URL anyone
holding it can fetch once, until it expires.

It imports the server's own signing function rather than reimplementing HMAC,
so the link and the route can never drift apart.

Usage, with the secret read straight off the host so it never reaches the
screen or the shell history:

    MFA_APP_DOWNLOAD_LINK_SECRET="$(ssh "$MFA_RELEASE_HOST" \\
        'sudo grep ^MFA_APP_DOWNLOAD_LINK_SECRET= /opt/mfa/infra/docker/.env \\
         | cut -d= -f2-')" \\
    MFA_BASE_URL=https://finance.example.com \\
        python3 tool/make_download_link.py --days 7

Rotating MFA_APP_DOWNLOAD_LINK_SECRET on the host withdraws every link ever
issued. There is no way to withdraw one and keep another.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

# Loaded as a lone module rather than imported from the package, whose
# __init__ pulls in FastAPI — this script must run with nothing installed.
_MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "services"
    / "api"
    / "src"
    / "mobile_finance_api"
    / "app_download_link.py"
)
_spec = importlib.util.spec_from_file_location("mfa_app_download_link", _MODULE_PATH)
if _spec is None or _spec.loader is None:  # pragma: no cover - packaging error
    raise SystemExit(f"cannot load {_MODULE_PATH}")
_link_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_link_module)

MINIMUM_SECRET_BYTES = _link_module.MINIMUM_SECRET_BYTES
sign_download_link = _link_module.sign_download_link

#: A link that outlives the reason it was made is a liability, not a
#: convenience. Long enough for someone to get round to installing; short
#: enough that a forwarded message stops working.
_MAXIMUM_DAYS = 30


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--days",
        type=int,
        default=7,
        help=f"how long the link stays valid, 1-{_MAXIMUM_DAYS} (default 7)",
    )
    arguments = parser.parse_args()
    if not 1 <= arguments.days <= _MAXIMUM_DAYS:
        print(f"--days must be between 1 and {_MAXIMUM_DAYS}", file=sys.stderr)
        return 2

    raw_secret = (os.environ.get("MFA_APP_DOWNLOAD_LINK_SECRET") or "").strip()
    if not raw_secret:
        print(
            "MFA_APP_DOWNLOAD_LINK_SECRET is required; it is the value set on "
            "the host, not a new one.",
            file=sys.stderr,
        )
        return 2
    secret = raw_secret.encode("utf-8")
    if len(secret) < MINIMUM_SECRET_BYTES:
        print(
            f"MFA_APP_DOWNLOAD_LINK_SECRET must contain at least "
            f"{MINIMUM_SECRET_BYTES} bytes",
            file=sys.stderr,
        )
        return 2

    base_url = (os.environ.get("MFA_BASE_URL") or "").strip().rstrip("/")
    if not base_url.startswith("https://"):
        print("MFA_BASE_URL is required and must be https", file=sys.stderr)
        return 2

    expires_at = datetime.now(UTC) + timedelta(days=arguments.days)
    link = sign_download_link(secret=secret, expires_at=expires_at)

    print(f"{base_url}/api/v1/app/get/{link}")
    print(
        f"\nValid until {expires_at:%Y-%m-%d %H:%M} UTC. Anyone holding this "
        "link can download the build;\ninstalling it grants nothing until the "
        "person's address is added to MFA_AUTH_REGISTRATION_ALLOWLIST.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
