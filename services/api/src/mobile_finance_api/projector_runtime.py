"""Standalone runtime for the deterministic Home outbox consumer."""

from __future__ import annotations

import argparse
import asyncio
import logging
import math
import time
from collections.abc import Sequence

from .config import require_database_url
from .database import create_database
from .postgres_home_projector import PostgresHomeProjector

_LOGGER = logging.getLogger("mobile_finance_api.home_projector")


async def _run_once(*, max_cycles: int | None) -> None:
    engine, session_factory = create_database(require_database_url())
    projector = PostgresHomeProjector(session_factory=session_factory)
    try:
        # Reconcile healthy users before a poison event can make the one-shot
        # scheduler exit non-zero. The pending user's reconciliation is
        # intentionally skipped until its event validates.
        reconciled = await projector.reconcile_all()
        consumed = await projector.drain_pending(max_cycles=max_cycles)
        _LOGGER.info(
            "Home projector cycle complete consumed=%d reconciled=%d",
            consumed,
            reconciled,
        )
    finally:
        await engine.dispose()


async def _run_forever(
    *,
    poll_seconds: float,
    reconcile_seconds: float,
    max_cycles: int,
) -> None:
    engine, session_factory = create_database(require_database_url())
    projector = PostgresHomeProjector(session_factory=session_factory)
    next_reconciliation = 0.0
    try:
        while True:
            consumed = 0
            try:
                consumed = await projector.drain_pending(max_cycles=max_cycles)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                # SQL exception strings may include bound financial values.
                # Log only the bounded exception type and continue with the
                # independent calendar reconciliation.
                _LOGGER.error(
                    "Home projector event cycle failed error_type=%s",
                    type(error).__name__,
                )

            now = time.monotonic()
            if now >= next_reconciliation:
                try:
                    reconciled = await projector.reconcile_all()
                    next_reconciliation = now + reconcile_seconds
                    _LOGGER.info(
                        "Home projector reconciliation complete published=%d",
                        reconciled,
                    )
                except asyncio.CancelledError:
                    raise
                except Exception as error:
                    _LOGGER.error(
                        "Home projector reconciliation failed error_type=%s",
                        type(error).__name__,
                    )
            if consumed == 0:
                await asyncio.sleep(poll_seconds)
    finally:
        await engine.dispose()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Consume Finance outboxes into immutable Home revisions.",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Reconcile accounts, drain pending events once, then exit.",
    )
    parser.add_argument(
        "--max-cycles",
        type=int,
        default=100,
        help="Maximum users processed between poll/reconciliation checks.",
    )
    parser.add_argument("--poll-seconds", type=float, default=2.0)
    parser.add_argument("--reconcile-seconds", type=float, default=300.0)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.max_cycles <= 0:
        raise SystemExit("--max-cycles must be positive")
    if (
        not math.isfinite(args.poll_seconds)
        or not math.isfinite(args.reconcile_seconds)
        or args.poll_seconds <= 0
        or args.reconcile_seconds <= 0
    ):
        raise SystemExit("poll and reconciliation intervals must be positive")
    logging.basicConfig(level=logging.INFO)
    if args.once:
        try:
            asyncio.run(_run_once(max_cycles=args.max_cycles))
        except Exception as error:
            _LOGGER.error(
                "Home projector one-shot failed error_type=%s",
                type(error).__name__,
            )
            return 1
    else:
        try:
            asyncio.run(
                _run_forever(
                    poll_seconds=args.poll_seconds,
                    reconcile_seconds=args.reconcile_seconds,
                    max_cycles=args.max_cycles,
                )
            )
        except KeyboardInterrupt:
            return 0
        except Exception as error:
            _LOGGER.error(
                "Home projector startup failed error_type=%s",
                type(error).__name__,
            )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
