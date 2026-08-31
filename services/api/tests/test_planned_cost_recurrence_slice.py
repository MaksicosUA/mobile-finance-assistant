"""The recurring planned cost slice, end to end below HTTP (ADR 0025).

A rule is intent, never money. These tests hold the boundary that keeps it that
way, and the lifecycle that finally makes `skipped` mean something different
from `cancelled`.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.main import create_app
from mobile_finance_api.planned_cost_recurrence_contracts import (
    CreatePlannedCostRecurrenceCommand,
    EndPlannedCostRecurrenceCommand,
    PlannedCostRecurrence,
    create_recurrence_command_hash,
    end_recurrence_command_hash,
    planned_cost_recurrence_contract_schema,
)
from mobile_finance_api.planned_cost_recurrence_core import (
    PlannedCostRecurrenceCore,
    RecurrenceAccountContext,
    RecurrenceAlreadyEnded,
    RecurrenceCommandConflict,
    RecurrenceEndResult,
    RecurrenceListing,
    RecurrenceNotFound,
    RecurrencePersistenceUnavailable,
    RecurrenceRejected,
    RecurrenceWriteResult,
    StoredRecurrence,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_OTHER_USER_ID = UUID("22222222-2222-4222-8222-222222222222")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")
_COMMAND_ID = UUID("44444444-4444-4444-8444-444444444444")
_RULE_ID = UUID("55555555-5555-4555-8555-555555555555")
_CATEGORY_ID = UUID("66666666-6666-4666-8666-666666666666")
_END_COMMAND_ID = UUID("77777777-7777-4777-8777-777777777777")
# 23:30 in Berlin on 15 January is already the 16th nowhere, but 23:30 UTC is
# 00:30 on the 16th in Berlin — which is the point of the timezone test below.
_NOW = datetime(2026, 1, 15, 23, 30, tzinfo=UTC)
_TIMEZONE = "Europe/Berlin"


def _clock() -> datetime:
    return _NOW


def _command(**changes: object) -> CreatePlannedCostRecurrenceCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_COMMAND_ID),
        "accountId": str(_ACCOUNT_ID),
        "amount": "800.00",
        "currency": "EUR",
        "title": "Аренда",
        "frequency": "monthly",
        "dayOfMonth": 31,
        "startsOn": "2026-01-01",
        "requestedAt": "2026-01-15T23:30:00Z",
    }
    payload.update(changes)
    return CreatePlannedCostRecurrenceCommand.model_validate(payload)


def _end_command(**changes: object) -> EndPlannedCostRecurrenceCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_END_COMMAND_ID),
        "requestedAt": "2026-01-15T23:30:00Z",
    }
    payload.update(changes)
    return EndPlannedCostRecurrenceCommand.model_validate(payload)


def _context(
    *,
    currency: str = "EUR",
    opening_balance_on: date = date(2025, 1, 1),
    canonical_timezone: str = _TIMEZONE,
) -> RecurrenceAccountContext:
    return RecurrenceAccountContext(
        account_id=_ACCOUNT_ID,
        user_id=_USER_ID,
        currency=currency,
        opening_balance_on=opening_balance_on,
        canonical_timezone=canonical_timezone,
    )


def _stored(
    *,
    status: str = "active",
    user_id: UUID = _USER_ID,
    day_of_month: int = 31,
    ends_on: date | None = None,
    category_id: UUID | None = None,
) -> StoredRecurrence:
    return StoredRecurrence(
        recurrence_id=_RULE_ID,
        user_id=user_id,
        account_id=_ACCOUNT_ID,
        command_id=_COMMAND_ID,
        amount=Decimal("800.00"),
        currency="EUR",
        title="Аренда",
        category=None,
        category_id=category_id,
        frequency="monthly",
        day_of_month=day_of_month,
        starts_on=date(2026, 1, 1),
        ends_on=ends_on,
        status=status,
        created_at=_NOW,
        updated_at=_NOW,
    )


class _Repository:
    """A recording double shaped like the PostgreSQL adapter."""

    def __init__(
        self,
        *,
        context: RecurrenceAccountContext | None = None,
        category_direction: str | None = None,
        replay: RecurrenceWriteResult | None = None,
        end_replay: RecurrenceEndResult | None = None,
        raises: Exception | None = None,
        end_raises: Exception | None = None,
        stored: StoredRecurrence | None = None,
        listing: tuple[RecurrenceListing, ...] = (),
    ) -> None:
        self._context = context
        self._category_direction = category_direction
        self._replay = replay
        self._end_replay = end_replay
        self._raises = raises
        self._end_raises = end_raises
        self._stored = stored
        self._listing = listing
        self.through: date | None = None
        self.created: list[UUID] = []
        self.ended: list[UUID] = []

    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> RecurrenceAccountContext | None:
        del user_id, account_id
        return self._context

    async def get_category_direction(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> str | None:
        del user_id, category_id
        return self._category_direction

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> RecurrenceWriteResult | None:
        del user_id, command_id, payload_hash
        return self._replay

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostRecurrenceCommand,
        payload_hash: bytes,
        through: date,
    ) -> RecurrenceWriteResult:
        del user_id, payload_hash
        if self._raises is not None:
            raise self._raises
        self.through = through
        self.created.append(command.command_id)
        from mobile_finance_api.planned_cost_recurrence import monthly_occurrences

        return RecurrenceWriteResult(
            recurrence=self._stored or _stored(day_of_month=command.day_of_month),
            occurrences=monthly_occurrences(
                day_of_month=command.day_of_month,
                starts_on=command.starts_on,
                ends_on=command.ends_on,
                through=through,
            ),
            idempotent_replay=False,
        )

    async def replay_existing_end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> RecurrenceEndResult | None:
        del user_id, recurrence_id, command_id, payload_hash
        return self._end_replay

    async def end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command: EndPlannedCostRecurrenceCommand,
        payload_hash: bytes,
    ) -> RecurrenceEndResult:
        del user_id, command, payload_hash
        if self._end_raises is not None:
            raise self._end_raises
        self.ended.append(recurrence_id)
        return RecurrenceEndResult(
            recurrence=self._stored or _stored(status="ended"),
            cancelled_occurrences=3,
            idempotent_replay=False,
        )

    async def list_recurrences(
        self,
        *,
        user_id: UUID,
    ) -> tuple[RecurrenceListing, ...]:
        del user_id
        return self._listing


def _core(repository: _Repository) -> PlannedCostRecurrenceCore:
    return PlannedCostRecurrenceCore(
        repository=repository,  # type: ignore[arg-type]
        clock=_clock,
    )


# --- creation -----------------------------------------------------------------


def test_a_rule_reports_the_dates_it_just_created() -> None:
    """Seeing where the 31st lands is how February stops being a surprise."""

    repository = _Repository(context=_context())
    result = asyncio.run(_core(repository).create(user_id=_USER_ID, command=_command()))

    assert result.idempotent_replay is False
    assert result.recurrence.day_of_month == 31
    assert result.occurrences[:3] == (
        date(2026, 1, 31),
        date(2026, 2, 28),
        date(2026, 3, 31),
    )


def test_the_horizon_is_measured_in_the_accounts_own_timezone() -> None:
    """23:30 UTC on the 15th is already the 16th in Berlin.

    The horizon is "three months from today", and which day it already is
    depends on where the account lives, not on where the server does.
    """

    berlin = _Repository(context=_context())
    asyncio.run(_core(berlin).create(user_id=_USER_ID, command=_command()))

    utc = _Repository(context=_context(canonical_timezone="UTC"))
    asyncio.run(_core(utc).create(user_id=_USER_ID, command=_command()))

    assert berlin.through == date(2026, 4, 16)
    assert utc.through == date(2026, 4, 15)


def test_an_unknown_account_is_refused_without_naming_it() -> None:
    repository = _Repository(context=None)
    with pytest.raises(RecurrenceRejected) as rejection:
        asyncio.run(_core(repository).create(user_id=_USER_ID, command=_command()))

    assert [issue.code for issue in rejection.value.issues] == ["ACCOUNT_UNAVAILABLE"]
    assert repository.created == []


def test_a_currency_the_account_does_not_use_is_refused() -> None:
    repository = _Repository(context=_context(currency="USD"))
    with pytest.raises(RecurrenceRejected) as rejection:
        asyncio.run(_core(repository).create(user_id=_USER_ID, command=_command()))

    assert [issue.code for issue in rejection.value.issues] == [
        "ACCOUNT_CURRENCY_MISMATCH"
    ]


def test_a_series_starting_before_the_account_existed_is_refused() -> None:
    """Such an instance could never be confirmed into a legal operation."""

    repository = _Repository(context=_context(opening_balance_on=date(2026, 6, 1)))
    with pytest.raises(RecurrenceRejected) as rejection:
        asyncio.run(_core(repository).create(user_id=_USER_ID, command=_command()))

    codes = [issue.code for issue in rejection.value.issues]
    assert codes == ["RECURRENCE_BEFORE_ACCOUNT_BASELINE"]
    assert rejection.value.issues[0].field == "startsOn"


def test_a_category_that_is_not_the_users_is_refused() -> None:
    repository = _Repository(context=_context(), category_direction=None)
    with pytest.raises(RecurrenceRejected) as rejection:
        asyncio.run(
            _core(repository).create(
                user_id=_USER_ID,
                command=_command(categoryId=str(_CATEGORY_ID)),
            )
        )

    assert [issue.code for issue in rejection.value.issues] == ["CATEGORY_UNAVAILABLE"]


def test_an_income_category_cannot_label_a_planned_cost() -> None:
    """A plan is an expense (ADR 0018); an income category on one is a mistake."""

    repository = _Repository(context=_context(), category_direction="income")
    with pytest.raises(RecurrenceRejected) as rejection:
        asyncio.run(
            _core(repository).create(
                user_id=_USER_ID,
                command=_command(categoryId=str(_CATEGORY_ID)),
            )
        )

    assert [issue.code for issue in rejection.value.issues] == [
        "CATEGORY_DIRECTION_MISMATCH"
    ]


def test_an_expense_category_is_accepted() -> None:
    repository = _Repository(
        context=_context(),
        category_direction="expense",
        stored=_stored(category_id=_CATEGORY_ID),
    )
    result = asyncio.run(
        _core(repository).create(
            user_id=_USER_ID,
            command=_command(categoryId=str(_CATEGORY_ID)),
        )
    )

    assert result.recurrence.category_id == _CATEGORY_ID


def test_no_category_asks_the_catalogue_nothing() -> None:
    """A rule without a link must not be refused for a category it never named."""

    repository = _Repository(context=_context(), category_direction=None)
    result = asyncio.run(_core(repository).create(user_id=_USER_ID, command=_command()))

    assert result.recurrence.category_id is None


def test_replaying_a_creation_returns_the_original_without_writing() -> None:
    replay = RecurrenceWriteResult(
        recurrence=_stored(),
        occurrences=(date(2026, 1, 31), date(2026, 2, 28)),
        idempotent_replay=True,
    )
    repository = _Repository(context=_context(), replay=replay)
    result = asyncio.run(_core(repository).create(user_id=_USER_ID, command=_command()))

    assert result.idempotent_replay is True
    assert result.occurrences == (date(2026, 1, 31), date(2026, 2, 28))
    assert repository.created == []


def test_a_rule_written_for_another_user_is_never_returned() -> None:
    repository = _Repository(context=_context(), stored=_stored(user_id=_OTHER_USER_ID))
    with pytest.raises(RecurrencePersistenceUnavailable):
        asyncio.run(_core(repository).create(user_id=_USER_ID, command=_command()))


# --- ending -------------------------------------------------------------------


def test_ending_a_series_reports_what_it_withdrew() -> None:
    repository = _Repository(stored=_stored(status="ended"))
    result = asyncio.run(
        _core(repository).end(
            user_id=_USER_ID,
            recurrence_id=_RULE_ID,
            command=_end_command(),
        )
    )

    assert result.recurrence.status == "ended"
    assert result.cancelled_occurrences == 3
    assert repository.ended == [_RULE_ID]


def test_ending_an_already_ended_series_is_refused() -> None:
    repository = _Repository(end_raises=RecurrenceAlreadyEnded())
    with pytest.raises(RecurrenceRejected) as rejection:
        asyncio.run(
            _core(repository).end(
                user_id=_USER_ID,
                recurrence_id=_RULE_ID,
                command=_end_command(),
            )
        )

    assert [issue.code for issue in rejection.value.issues] == [
        "INVALID_LIFECYCLE_TRANSITION"
    ]


def test_replaying_an_ending_returns_the_original_count() -> None:
    repository = _Repository(
        end_replay=RecurrenceEndResult(
            recurrence=_stored(status="ended"),
            cancelled_occurrences=2,
            idempotent_replay=True,
        )
    )
    result = asyncio.run(
        _core(repository).end(
            user_id=_USER_ID,
            recurrence_id=_RULE_ID,
            command=_end_command(),
        )
    )

    assert result.idempotent_replay is True
    assert result.cancelled_occurrences == 2
    assert repository.ended == []


def test_listing_refuses_a_row_belonging_to_someone_else() -> None:
    repository = _Repository(
        listing=(
            RecurrenceListing(
                recurrence=_stored(user_id=_OTHER_USER_ID),
                upcoming=(),
            ),
        )
    )
    with pytest.raises(RecurrencePersistenceUnavailable):
        asyncio.run(_core(repository).list_recurrences(user_id=_USER_ID))


# --- the contract -------------------------------------------------------------


def test_a_series_that_ends_before_it_begins_is_malformed() -> None:
    with pytest.raises(ValidationError):
        _command(startsOn="2026-05-01", endsOn="2026-01-01")


def test_an_impossible_anchor_day_is_malformed() -> None:
    with pytest.raises(ValidationError):
        _command(dayOfMonth=32)
    with pytest.raises(ValidationError):
        _command(dayOfMonth=0)


def test_the_29th_30th_and_31st_are_all_accepted() -> None:
    """Refusing them was one of the rejected answers to February (ADR 0025)."""

    for day in (29, 30, 31):
        assert _command(dayOfMonth=day).day_of_month == day


def test_an_unknown_key_is_refused_rather_than_ignored() -> None:
    with pytest.raises(ValidationError):
        _command(everyOtherMonth=True)


def test_money_crosses_the_contract_as_a_decimal_string() -> None:
    rule = PlannedCostRecurrence(
        recurrence_id=_RULE_ID,
        user_id=_USER_ID,
        account_id=_ACCOUNT_ID,
        command_id=_COMMAND_ID,
        amount=Decimal("800.00"),
        currency="EUR",
        title="Аренда",
        category=None,
        category_id=None,
        frequency="monthly",
        day_of_month=31,
        starts_on=date(2026, 1, 1),
        ends_on=None,
        status="active",
        created_at=_NOW,
        updated_at=_NOW,
    )
    payload = rule.model_dump(mode="json", by_alias=True)

    # Normalised, but never a JSON float: the client formats, it never
    # recalculates.
    assert isinstance(payload["amount"], str)
    assert Decimal(payload["amount"]) == Decimal("800.00")


def test_the_command_hash_binds_every_field() -> None:
    baseline = create_recurrence_command_hash(_command())

    assert create_recurrence_command_hash(_command(dayOfMonth=15)) != baseline
    assert create_recurrence_command_hash(_command(amount="801.00")) != baseline
    assert create_recurrence_command_hash(_command(endsOn="2027-01-01")) != baseline
    assert create_recurrence_command_hash(_command()) == baseline


def test_an_ending_hash_is_bound_to_its_own_rule() -> None:
    """Replaying one ending against a different rule must be a conflict."""

    command = _end_command()
    assert end_recurrence_command_hash(
        recurrence_id=_RULE_ID,
        command=command,
    ) != end_recurrence_command_hash(recurrence_id=uuid4(), command=command)


def test_the_schema_is_reproducible() -> None:
    assert planned_cost_recurrence_contract_schema() == (
        planned_cost_recurrence_contract_schema()
    )


# --- over HTTP ----------------------------------------------------------------


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(
            subject=str(_USER_ID),
            display_name="Synthetic User",
        )


def _application(core: PlannedCostRecurrenceCore):  # type: ignore[no-untyped-def]
    return create_app(
        planned_cost_recurrence_core=core,
        current_user_authenticator=_StaticAuthenticator(),
    )


async def _post(app: object, path: str, body: dict[str, object]):  # type: ignore[no-untyped-def]
    async with AsyncClient(
        transport=ASGITransport(app=app),  # type: ignore[arg-type]
        base_url="http://test",
    ) as client:
        return await client.post(
            path,
            json=body,
            headers={"Authorization": "Bearer synthetic"},
        )


def _create_body(**changes: object) -> dict[str, object]:
    body: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_COMMAND_ID),
        "accountId": str(_ACCOUNT_ID),
        "amount": "800.00",
        "currency": "EUR",
        "title": "Аренда",
        "frequency": "monthly",
        "dayOfMonth": 31,
        "startsOn": "2026-01-01",
        "requestedAt": "2026-01-15T23:30:00Z",
    }
    body.update(changes)
    return body


def test_creating_a_rule_answers_201_with_its_dates() -> None:
    async def scenario() -> None:
        core = _core(_Repository(context=_context()))
        response = await _post(
            _application(core),
            "/api/v1/planned-cost-recurrences",
            _create_body(),
        )

        assert response.status_code == 201
        payload = response.json()
        assert payload["recurrence"]["dayOfMonth"] == 31
        assert payload["occurrences"][:2] == ["2026-01-31", "2026-02-28"]

    asyncio.run(scenario())


def test_a_replay_answers_200_rather_than_creating_again() -> None:
    async def scenario() -> None:
        core = _core(
            _Repository(
                context=_context(),
                replay=RecurrenceWriteResult(
                    recurrence=_stored(),
                    occurrences=(date(2026, 1, 31),),
                    idempotent_replay=True,
                ),
            )
        )
        response = await _post(
            _application(core),
            "/api/v1/planned-cost-recurrences",
            _create_body(),
        )

        assert response.status_code == 200
        assert response.json()["idempotentReplay"] is True

    asyncio.run(scenario())


def test_a_reused_command_with_different_content_is_a_conflict() -> None:
    async def scenario() -> None:
        # In the adapter the replay lookup usually raises this; a lost race
        # makes the write raise it instead, and both must reach the caller as
        # one conflict rather than a second accepted rule.
        core = _core(
            _Repository(context=_context(), raises=RecurrenceCommandConflict())
        )
        response = await _post(
            _application(core),
            "/api/v1/planned-cost-recurrences",
            _create_body(),
        )

        assert response.status_code == 409
        assert response.json()["detail"]["code"] == "COMMAND_CONFLICT"

    asyncio.run(scenario())


def test_a_rejection_carries_typed_codes_and_no_user_text() -> None:
    async def scenario() -> None:
        core = _core(_Repository(context=None))
        response = await _post(
            _application(core),
            "/api/v1/planned-cost-recurrences",
            _create_body(title="Аренда квартиры на Гагарина"),
        )

        assert response.status_code == 422
        body = response.text
        assert "Гагарина" not in body
        assert "800.00" not in body
        detail = response.json()["detail"]
        assert detail["code"] == "RECURRENCE_REJECTED"
        assert detail["issues"] == [
            {"code": "ACCOUNT_UNAVAILABLE", "field": "accountId"}
        ]

    asyncio.run(scenario())


def test_ending_an_unknown_rule_answers_404() -> None:
    async def scenario() -> None:
        core = _core(_Repository(end_raises=RecurrenceNotFound()))
        response = await _post(
            _application(core),
            f"/api/v1/planned-cost-recurrences/{_RULE_ID}/end",
            {
                "schemaVersion": "1",
                "commandId": str(_END_COMMAND_ID),
                "requestedAt": "2026-01-15T23:30:00Z",
            },
        )

        assert response.status_code == 404
        assert response.json()["detail"]["code"] == "RECURRENCE_NOT_FOUND"

    asyncio.run(scenario())


def test_an_unwired_deployment_answers_503_rather_than_pretending() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        response = await _post(
            app,
            "/api/v1/planned-cost-recurrences",
            _create_body(),
        )

        assert response.status_code == 503
        assert response.json()["detail"]["code"] == "RECURRENCE_PERSISTENCE_UNAVAILABLE"

    asyncio.run(scenario())


def test_an_anonymous_caller_is_refused() -> None:
    async def scenario() -> None:
        core = _core(_Repository(context=_context()))
        # No authenticator wired at all: the app fails closed rather than
        # treating an unauthenticated caller as anybody.
        app = create_app(planned_cost_recurrence_core=core)
        async with AsyncClient(
            transport=ASGITransport(app=app),  # type: ignore[arg-type]
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/planned-cost-recurrences",
                json=_create_body(),
            )

        assert response.status_code == 401

    asyncio.run(scenario())
