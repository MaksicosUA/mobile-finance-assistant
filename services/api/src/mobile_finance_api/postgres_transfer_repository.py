"""PostgreSQL persistence for a confirmed transfer between two wallets.

The transfer, its audit row and its identifier-only Home invalidation are
written in one transaction, the same shape every other accepted write uses
(ADR 0008). Nothing here converts anything: both amounts are stored exactly as
they were witnessed (ADR 0029).
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import select

from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountRow,
    FinanceTransferAuditRow,
    FinanceTransferOutboxEventRow,
    FinanceTransferRow,
)
from .transfer_contracts import CommittedTransfer, TransferDraft
from .transfer_core import (
    TransferCommandConflict,
    TransferPersistenceUnavailable,
    TransferWalletSnapshot,
    TransferWriteResult,
)


class PostgresTransferRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    async def get_transfer_wallets(
        self,
        *,
        user_id: UUID,
        account_ids: tuple[UUID, ...],
    ) -> tuple[TransferWalletSnapshot, ...]:
        async with self._session_factory() as database:
            rows = (
                await database.scalars(
                    select(FinanceAccountRow).where(
                        FinanceAccountRow.user_id == user_id,
                        FinanceAccountRow.status == "active",
                        FinanceAccountRow.id.in_(account_ids),
                    )
                )
            ).all()
        return tuple(
            TransferWalletSnapshot(
                account_id=row.id,
                currency=row.currency,
                opening_balance_on=row.opening_balance_on,
            )
            for row in rows
        )

    async def replay_transfer(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> TransferWriteResult | None:
        if len(payload_hash) != 32:
            raise TransferPersistenceUnavailable
        async with self._session_factory() as database:
            existing = await database.scalar(
                select(FinanceTransferRow).where(
                    FinanceTransferRow.user_id == user_id,
                    FinanceTransferRow.command_id == command_id,
                )
            )
        if existing is None:
            return None
        # The same identity with different content is a conflict, never a
        # second transfer: that is what makes a retry safe (ADR 0008).
        if existing.command_payload_hash != payload_hash:
            raise TransferCommandConflict
        return TransferWriteResult(
            transfer=_to_contract(existing), idempotent_replay=True
        )

    async def commit_transfer(
        self,
        *,
        user_id: UUID,
        draft: TransferDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> TransferWriteResult:
        if len(payload_hash) != 32:
            raise TransferPersistenceUnavailable
        created_at = _aware_utc(self._clock())
        transfer_id = uuid4()

        async with self._session_factory() as database:
            async with database.begin():
                existing = await database.scalar(
                    select(FinanceTransferRow)
                    .where(
                        FinanceTransferRow.user_id == user_id,
                        FinanceTransferRow.command_id == draft.command_id,
                    )
                    .with_for_update()
                )
                if existing is not None:
                    if existing.command_payload_hash != payload_hash:
                        raise TransferCommandConflict
                    return TransferWriteResult(
                        transfer=_to_contract(existing), idempotent_replay=True
                    )

                transfer = FinanceTransferRow(
                    id=transfer_id,
                    user_id=user_id,
                    command_id=draft.command_id,
                    command_payload_hash=payload_hash,
                    schema_version=draft.schema_version,
                    from_account_id=draft.from_account_id,
                    from_amount=draft.from_amount,
                    from_currency=draft.from_currency,
                    to_account_id=draft.to_account_id,
                    to_amount=draft.to_amount,
                    to_currency=draft.to_currency,
                    captured_at=_aware_utc(draft.captured_at),
                    captured_timezone=draft.captured_timezone,
                    occurred_on=draft.occurred_on,
                    status="confirmed",
                    confirmed_at=_aware_utc(confirmed_at),
                    created_at=created_at,
                )
                database.add(transfer)
                # Flushed before the rows whose composite foreign keys point at
                # it: nothing relates the mappers, so the unit of work is free
                # to insert them first and the keys then refuse them.
                await database.flush()
                database.add_all(
                    [
                        FinanceTransferAuditRow(
                            id=uuid4(),
                            transfer_id=transfer_id,
                            user_id=user_id,
                            command_id=draft.command_id,
                            event_type="transfer_confirmed",
                            actor_type="user",
                            payload_hash=payload_hash,
                            created_at=created_at,
                        ),
                        FinanceTransferOutboxEventRow(
                            id=uuid4(),
                            aggregate_type="finance_transfer",
                            aggregate_id=transfer_id,
                            user_id=user_id,
                            command_id=draft.command_id,
                            event_type="finance.transfer.accepted.v1",
                            # Identifiers only. The projector rebuilds from
                            # authoritative facts and never trusts a payload
                            # to carry money (ADR 0011).
                            payload={
                                "schemaVersion": "1",
                                "transferId": str(transfer_id),
                                "userId": str(user_id),
                                "commandId": str(draft.command_id),
                            },
                            created_at=created_at,
                            published_at=None,
                            attempt_count=0,
                            validation_failure_count=0,
                            next_attempt_at=created_at,
                            last_failed_at=None,
                            failure_code=None,
                            dead_lettered_at=None,
                        ),
                    ]
                )
                result = TransferWriteResult(
                    transfer=_to_contract(transfer), idempotent_replay=False
                )
        return result


def _to_contract(row: FinanceTransferRow) -> CommittedTransfer:
    return CommittedTransfer(
        transfer_id=row.id,
        user_id=row.user_id,
        command_id=row.command_id,
        from_account_id=row.from_account_id,
        from_amount=row.from_amount,
        from_currency=row.from_currency,
        to_account_id=row.to_account_id,
        to_amount=row.to_amount,
        to_currency=row.to_currency,
        occurred_on=row.occurred_on,
        status="confirmed",
        confirmed_at=row.confirmed_at,
        created_at=row.created_at,
    )


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("timestamp must be timezone-aware")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
