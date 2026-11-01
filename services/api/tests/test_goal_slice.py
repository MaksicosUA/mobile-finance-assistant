from __future__ import annotations

import asyncio
import json
from datetime import UTC, date, datetime
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.goal_contracts import (
    CancelGoalCommand,
    CreateGoalCommand,
    Goal,
    RecordGoalContributionCommand,
    apply_contribution,
    cancel_goal_command_hash,
    contribution_command_hash,
    create_goal_command_hash,
    derive_achieved,
    derive_goal_balance,
    derive_progress_percent,
    goal_contract_schema,
)
from mobile_finance_api.goal_core import (
    ContributionWriteResult,
    GoalAccountContext,
    GoalCommandConflict,
    GoalCore,
    GoalLedgerSnapshot,
    GoalListSnapshot,
    GoalNotActive,
    GoalNotFound,
    GoalPersistenceUnavailable,
    GoalRejected,
    GoalWithdrawalExceedsBalance,
    GoalWriteResult,
    StoredGoal,
    StoredGoalContribution,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.postgres_goal_repository import _outbox_payload

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_OTHER_USER_ID = UUID("22222222-2222-4222-8222-222222222222")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")
_GOAL_ID = UUID("55555555-5555-4555-8555-555555555555")
_COMMAND_ID = UUID("44444444-4444-4444-8444-444444444444")
_NOW = datetime(2026, 8, 11, 12, 0, tzinfo=UTC)
_TIMEZONE = "Europe/Berlin"


def _clock() -> datetime:
    return _NOW


def _command(**changes: object) -> CreateGoalCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_COMMAND_ID),
        "accountId": str(_ACCOUNT_ID),
        "title": "Отпуск",
        "targetAmount": "3000.00",
        "currency": "EUR",
        "targetOn": "2027-06-01",
        "monthlyContribution": "250.00",
        "requestedAt": "2026-08-11T12:00:00Z",
    }
    payload.update(changes)
    return CreateGoalCommand.model_validate(payload)


def _cancel(**changes: object) -> CancelGoalCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": "77777777-7777-4777-8777-777777777777",
        "requestedAt": "2026-08-11T12:00:00Z",
    }
    payload.update(changes)
    return CancelGoalCommand.model_validate(payload)


def _contribution(**changes: object) -> RecordGoalContributionCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": "88888888-8888-4888-8888-888888888888",
        "direction": "deposit",
        "amount": "200.00",
        "requestedAt": "2026-08-11T12:00:00Z",
    }
    payload.update(changes)
    return RecordGoalContributionCommand.model_validate(payload)


def _context(
    *,
    currency: str = "EUR",
    opening_balance_on: date = date(2026, 1, 1),
    timezone: str = _TIMEZONE,
) -> GoalAccountContext:
    return GoalAccountContext(
        account_id=_ACCOUNT_ID,
        user_id=_USER_ID,
        currency=currency,
        opening_balance_on=opening_balance_on,
        canonical_timezone=timezone,
    )


def _stored(
    *,
    current: Decimal = Decimal(0),
    target: Decimal = Decimal("3000.00"),
    status: str = "active",
    user_id: UUID = _USER_ID,
) -> StoredGoal:
    return StoredGoal(
        goal_id=_GOAL_ID,
        user_id=user_id,
        account_id=_ACCOUNT_ID,
        command_id=_COMMAND_ID,
        title="Отпуск",
        target_amount=target,
        monthly_contribution=Decimal("250.00"),
        current_amount=current,
        currency="EUR",
        target_on=date(2027, 6, 1),
        status=status,
        created_at=_NOW,
        updated_at=_NOW,
        canonical_timezone=_TIMEZONE,
    )


# --- contract rules --------------------------------------------------------


@pytest.mark.parametrize(
    "amount",
    [0, 3000.0, "0", "0.0", "-1", "1e2", "NaN", "Infinity"],
)
def test_target_requires_a_positive_plain_decimal_string(amount: object) -> None:
    with pytest.raises(ValidationError):
        _command(targetAmount=amount)


def test_a_declared_monthly_intent_is_omitted_rather_than_zero() -> None:
    """One way to say "no plan", so absence cannot be expressed two ways."""

    assert _command(monthlyContribution=None).monthly_contribution is None
    with pytest.raises(ValidationError):
        _command(monthlyContribution="0")


def test_contract_rejects_mass_assignment_and_naive_time() -> None:
    with pytest.raises(ValidationError):
        _command(userId=str(uuid4()))
    with pytest.raises(ValidationError):
        _command(goalId=str(uuid4()))
    # A client must never be able to assert the derived balance itself.
    with pytest.raises(ValidationError):
        _command(currentAmount="500.00")
    with pytest.raises(ValidationError):
        _command(requestedAt="2026-08-11T12:00:00")


def test_title_is_required_and_control_characters_are_refused() -> None:
    with pytest.raises(ValidationError):
        _command(title="")
    with pytest.raises(ValidationError):
        _command(title="Отпуск\u0007")
    with pytest.raises(ValidationError):
        _command(title="О" * 101)
    assert _command(title="  Отпуск  ").title == "Отпуск"


def test_a_ledger_entry_has_a_direction_and_a_positive_amount() -> None:
    with pytest.raises(ValidationError):
        _contribution(direction="transfer")
    with pytest.raises(ValidationError):
        _contribution(amount="0")
    with pytest.raises(ValidationError):
        _contribution(amount="-50.00")
    assert _contribution(direction="withdrawal").direction == "withdrawal"
    # Omitted means "today in the account timezone", resolved by the server.
    assert _contribution().occurred_on is None


def test_goal_view_rejects_figures_that_contradict_its_ledger() -> None:
    base: dict[str, object] = {
        "goalId": str(_GOAL_ID),
        "userId": str(_USER_ID),
        "accountId": str(_ACCOUNT_ID),
        "commandId": str(_COMMAND_ID),
        "title": "Отпуск",
        "targetAmount": "3000.00",
        "currentAmount": "0",
        "monthlyContribution": "250.00",
        "currency": "EUR",
        "targetOn": "2027-06-01",
        "status": "active",
        "achieved": False,
        "progressPercent": "0",
        "createdAt": "2026-08-11T12:00:00Z",
        "updatedAt": "2026-08-11T12:00:00Z",
    }
    assert Goal.model_validate(base).current_amount == Decimal(0)
    # `achieved` must follow the amounts, never be asserted independently.
    with pytest.raises(ValidationError):
        Goal.model_validate({**base, "achieved": True})
    with pytest.raises(ValidationError):
        Goal.model_validate({**base, "currentAmount": "3000.00", "achieved": False})
    with pytest.raises(ValidationError):
        Goal.model_validate({**base, "currentAmount": "-1"})
    with pytest.raises(ValidationError):
        Goal.model_validate({**base, "progressPercent": "101"})
    with pytest.raises(ValidationError):
        Goal.model_validate({**base, "updatedAt": "2026-08-11T11:59:00Z"})


def test_create_hash_covers_every_field_of_the_command() -> None:
    baseline = create_goal_command_hash(_command())
    assert baseline == create_goal_command_hash(_command())
    for change in (
        {"targetAmount": "3000.01"},
        {"targetOn": "2027-06-02"},
        {"title": "Отпуск в горах"},
        {"monthlyContribution": None},
        {"requestedAt": "2026-08-11T12:00:01Z"},
    ):
        assert create_goal_command_hash(_command(**change)) != baseline


def test_goal_scoped_hashes_bind_the_command_to_one_goal() -> None:
    cancel = _cancel()
    assert cancel_goal_command_hash(
        goal_id=_GOAL_ID, command=cancel
    ) != cancel_goal_command_hash(goal_id=uuid4(), command=cancel)

    entry = _contribution()
    assert contribution_command_hash(
        goal_id=_GOAL_ID, command=entry
    ) != contribution_command_hash(goal_id=uuid4(), command=entry)
    # A cancellation and a contribution are different facts even when a client
    # reuses one command id, so their hashes must not collide.
    assert cancel_goal_command_hash(
        goal_id=_GOAL_ID, command=cancel
    ) != contribution_command_hash(goal_id=_GOAL_ID, command=entry)


# --- derivation rules ------------------------------------------------------


def test_balance_is_deposits_minus_withdrawals() -> None:
    entries = (
        ("deposit", Decimal("200.00")),
        ("deposit", Decimal("300.00")),
        ("withdrawal", Decimal("120.00")),
    )
    assert derive_goal_balance(entries) == Decimal("380.00")
    assert derive_goal_balance(()) == Decimal(0)


def test_apply_contribution_matches_the_full_ledger_sum() -> None:
    """The incremental fold and the full sum must never disagree."""

    entries = (
        ("deposit", Decimal("10.50")),
        ("withdrawal", Decimal("0.50")),
        ("deposit", Decimal("100")),
    )
    running = Decimal(0)
    for direction, amount in entries:
        running = apply_contribution(
            current=running,
            direction=direction,
            amount=amount,
        )
    assert running == derive_goal_balance(entries)


def test_progress_saturates_at_100_while_the_amount_stays_honest() -> None:
    target = Decimal("3000.00")
    assert derive_progress_percent(current=Decimal(0), target=target) == Decimal(0)
    assert derive_progress_percent(
        current=Decimal("1500.00"), target=target
    ) == Decimal(50)
    over = derive_progress_percent(current=Decimal("4500.00"), target=target)
    assert over == Decimal(100)
    assert derive_achieved(current=Decimal("4500.00"), target=target) is True
    # Over-funding is visible in the amount, which is never capped.
    assert _stored(current=Decimal("4500.00")).current_amount == Decimal("4500.00")


def test_progress_never_rounds_a_goal_up_to_complete() -> None:
    """One cent short must not display as finished."""

    almost = derive_progress_percent(
        current=Decimal("2999.99"),
        target=Decimal("3000.00"),
    )
    assert almost < Decimal(100)
    assert derive_achieved(current=Decimal("2999.99"), target=Decimal("3000.00")) is (
        False
    )


def test_progress_fits_the_numeric_bounds_of_the_projection() -> None:
    # 1/3 is the classic non-terminating case; it must still fit NUMERIC(38,18).
    ratio = derive_progress_percent(current=Decimal(1), target=Decimal(3))
    exponent = ratio.as_tuple().exponent
    assert isinstance(exponent, int)
    assert -exponent <= 18
    assert Decimal("33.3") < ratio < Decimal("33.4")


def test_a_withdrawal_that_empties_a_goal_leaves_it_at_zero_not_negative() -> None:
    balance = derive_goal_balance(
        (("deposit", Decimal("200.00")), ("withdrawal", Decimal("200.00")))
    )
    assert balance == Decimal(0)
    assert derive_progress_percent(current=balance, target=Decimal(100)) == Decimal(0)
    assert derive_achieved(current=balance, target=Decimal(100)) is False


# --- creation rules --------------------------------------------------------


def test_a_new_goal_starts_empty_and_unachieved() -> None:
    repository = _FakeRepository(context=_context())
    core = GoalCore(repository=repository, clock=_clock)
    response = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    assert response.goal.current_amount == Decimal(0)
    assert response.goal.progress_percent == Decimal(0)
    assert response.goal.achieved is False
    assert response.goal.status == "active"
    assert response.idempotent_replay is False


def test_an_undeclared_monthly_intent_is_stored_as_zero() -> None:
    repository = _FakeRepository(context=_context())
    core = GoalCore(repository=repository, clock=_clock)
    response = asyncio.run(
        core.create(user_id=_USER_ID, command=_command(monthlyContribution=None))
    )
    assert response.goal.monthly_contribution == Decimal(0)


@pytest.mark.parametrize(
    ("changes", "context", "expected"),
    [
        ({}, None, ("ACCOUNT_UNAVAILABLE", "accountId")),
        ({}, _context(currency="USD"), ("ACCOUNT_CURRENCY_MISMATCH", "currency")),
        (
            {"targetOn": "2025-12-31"},
            _context(opening_balance_on=date(2026, 1, 1)),
            ("TARGET_BEFORE_ACCOUNT_BASELINE", "targetOn"),
        ),
    ],
)
def test_creation_is_rejected_deterministically(
    changes: dict[str, object],
    context: GoalAccountContext | None,
    expected: tuple[str, str],
) -> None:
    repository = _FakeRepository(context=context)
    core = GoalCore(repository=repository, clock=_clock)
    with pytest.raises(GoalRejected) as rejection:
        asyncio.run(core.create(user_id=_USER_ID, command=_command(**changes)))
    assert expected in [(issue.code, issue.field) for issue in rejection.value.issues]
    assert repository.writes == 0


def test_a_goal_takes_the_currency_of_its_wallet() -> None:
    """A first wallet may be in anything, so a goal may be too (issue 0013)."""

    repository = _FakeRepository(context=_context(currency="USD"))
    core = GoalCore(repository=repository, clock=_clock)
    response = asyncio.run(
        core.create(user_id=_USER_ID, command=_command(currency="USD"))
    )
    assert response.goal.currency == "USD"
    assert repository.writes == 1


def test_exact_replay_returns_the_original_and_writes_nothing() -> None:
    repository = _FakeRepository(context=_context())
    core = GoalCore(repository=repository, clock=_clock)
    first = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    replay = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    assert replay.idempotent_replay is True
    assert replay.goal.goal_id == first.goal.goal_id
    assert repository.writes == 1


def test_same_command_with_different_content_is_a_conflict() -> None:
    repository = _FakeRepository(context=_context())
    core = GoalCore(repository=repository, clock=_clock)
    asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    with pytest.raises(GoalCommandConflict):
        asyncio.run(
            core.create(user_id=_USER_ID, command=_command(targetAmount="4000.00"))
        )
    assert repository.writes == 1


def test_a_foreign_result_fails_closed() -> None:
    repository = _FakeRepository(context=_context(), forced_user_id=_OTHER_USER_ID)
    core = GoalCore(repository=repository, clock=_clock)
    with pytest.raises(GoalPersistenceUnavailable):
        asyncio.run(core.create(user_id=_USER_ID, command=_command()))


# --- ledger rules ----------------------------------------------------------


def _created(repository: _FakeRepository) -> tuple[GoalCore, UUID]:
    core = GoalCore(repository=repository, clock=_clock)
    created = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    return core, created.goal.goal_id


def test_a_deposit_raises_the_derived_balance_and_progress() -> None:
    core, goal_id = _created(_FakeRepository(context=_context()))
    response = asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=goal_id,
            command=_contribution(amount="1500.00"),
        )
    )
    assert response.contribution.direction == "deposit"
    assert response.goal.current_amount == Decimal("1500.00")
    assert response.goal.progress_percent == Decimal(50)
    assert response.goal.achieved is False


def test_a_withdrawal_lowers_the_balance_without_erasing_history() -> None:
    repository = _FakeRepository(context=_context())
    core, goal_id = _created(repository)
    asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=goal_id,
            command=_contribution(amount="500.00"),
        )
    )
    asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=goal_id,
            command=_contribution(
                commandId=str(uuid4()),
                direction="withdrawal",
                amount="200.00",
            ),
        )
    )
    ledger = asyncio.run(core.list_contributions(user_id=_USER_ID, goal_id=goal_id))
    assert ledger.goal.current_amount == Decimal("300.00")
    # Both facts survive: the ledger is the evidence behind the figure.
    assert [entry.direction for entry in ledger.contributions] == [
        "deposit",
        "withdrawal",
    ]


def test_a_withdrawal_beyond_the_balance_is_refused() -> None:
    repository = _FakeRepository(context=_context())
    core, goal_id = _created(repository)
    asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=goal_id,
            command=_contribution(amount="100.00"),
        )
    )
    with pytest.raises(GoalRejected) as rejection:
        asyncio.run(
            core.record_contribution(
                user_id=_USER_ID,
                goal_id=goal_id,
                command=_contribution(
                    commandId=str(uuid4()),
                    direction="withdrawal",
                    amount="100.01",
                ),
            )
        )
    assert [issue.code for issue in rejection.value.issues] == [
        "WITHDRAWAL_EXCEEDS_GOAL_BALANCE"
    ]


def test_the_row_lock_refuses_a_racing_withdrawal_the_core_let_through() -> None:
    """The pre-check is convenience; the lock is what makes it correct."""

    repository = _FakeRepository(context=_context(), stale_balance=Decimal("1000.00"))
    core, goal_id = _created(repository)
    with pytest.raises(GoalRejected) as rejection:
        asyncio.run(
            core.record_contribution(
                user_id=_USER_ID,
                goal_id=goal_id,
                command=_contribution(direction="withdrawal", amount="900.00"),
            )
        )
    assert [issue.code for issue in rejection.value.issues] == [
        "WITHDRAWAL_EXCEEDS_GOAL_BALANCE"
    ]


def test_an_omitted_date_resolves_to_today_in_the_account_timezone() -> None:
    # 2026-08-11T22:00Z is already the 12th in Auckland, so a contribution with
    # no date must be recorded on the 12th rather than on the UTC date.
    repository = _FakeRepository(context=_context(timezone="Pacific/Auckland"))
    core = GoalCore(
        repository=repository,
        clock=lambda: datetime(2026, 8, 11, 22, 0, tzinfo=UTC),
    )
    created = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    response = asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=created.goal.goal_id,
            command=_contribution(),
        )
    )
    assert response.contribution.occurred_on == date(2026, 8, 12)


@pytest.mark.parametrize(
    ("changes", "expected"),
    [
        ({"occurredOn": "2026-08-12"}, ("FUTURE_CONTRIBUTION_DATE", "occurredOn")),
        (
            {"occurredOn": "2025-12-31"},
            ("CONTRIBUTION_BEFORE_ACCOUNT_BASELINE", "occurredOn"),
        ),
    ],
)
def test_a_contribution_date_is_bounded_by_today_and_the_baseline(
    changes: dict[str, object],
    expected: tuple[str, str],
) -> None:
    repository = _FakeRepository(context=_context())
    core, goal_id = _created(repository)
    with pytest.raises(GoalRejected) as rejection:
        asyncio.run(
            core.record_contribution(
                user_id=_USER_ID,
                goal_id=goal_id,
                command=_contribution(**changes),
            )
        )
    assert expected in [(issue.code, issue.field) for issue in rejection.value.issues]


def test_replaying_a_contribution_returns_the_original_entry() -> None:
    repository = _FakeRepository(context=_context())
    core, goal_id = _created(repository)
    first = asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=goal_id,
            command=_contribution(),
        )
    )
    replay = asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=goal_id,
            command=_contribution(),
        )
    )
    assert replay.idempotent_replay is True
    assert replay.contribution.contribution_id == first.contribution.contribution_id
    # The retried entry must not be counted twice.
    assert replay.goal.current_amount == Decimal("200.00")
    assert repository.contributions == 1


def test_a_reused_contribution_command_with_new_content_is_a_conflict() -> None:
    repository = _FakeRepository(context=_context())
    core, goal_id = _created(repository)
    asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=goal_id,
            command=_contribution(),
        )
    )
    with pytest.raises(GoalCommandConflict):
        asyncio.run(
            core.record_contribution(
                user_id=_USER_ID,
                goal_id=goal_id,
                command=_contribution(amount="900.00"),
            )
        )
    assert repository.contributions == 1


def test_a_contribution_to_an_unknown_goal_is_not_found() -> None:
    repository = _FakeRepository(context=_context())
    core = GoalCore(repository=repository, clock=_clock)
    with pytest.raises(GoalNotFound):
        asyncio.run(
            core.record_contribution(
                user_id=_USER_ID,
                goal_id=uuid4(),
                command=_contribution(),
            )
        )


# --- lifecycle rules -------------------------------------------------------


def test_cancelling_keeps_the_ledger_and_stops_new_contributions() -> None:
    repository = _FakeRepository(context=_context())
    core, goal_id = _created(repository)
    asyncio.run(
        core.record_contribution(
            user_id=_USER_ID,
            goal_id=goal_id,
            command=_contribution(amount="500.00"),
        )
    )
    cancelled = asyncio.run(
        core.cancel(user_id=_USER_ID, goal_id=goal_id, command=_cancel())
    )
    assert cancelled.goal.status == "cancelled"
    # The money really was set aside; erasing the evidence would make the audit
    # trail lie about what happened.
    assert cancelled.goal.current_amount == Decimal("500.00")

    with pytest.raises(GoalRejected) as rejection:
        asyncio.run(
            core.record_contribution(
                user_id=_USER_ID,
                goal_id=goal_id,
                command=_contribution(commandId=str(uuid4())),
            )
        )
    assert [issue.code for issue in rejection.value.issues] == ["GOAL_NOT_ACTIVE"]


def test_cancelling_twice_is_refused_but_an_exact_replay_is_not() -> None:
    repository = _FakeRepository(context=_context())
    core, goal_id = _created(repository)
    asyncio.run(core.cancel(user_id=_USER_ID, goal_id=goal_id, command=_cancel()))

    replay = asyncio.run(
        core.cancel(user_id=_USER_ID, goal_id=goal_id, command=_cancel())
    )
    assert replay.idempotent_replay is True

    with pytest.raises(GoalRejected) as rejection:
        asyncio.run(
            core.cancel(
                user_id=_USER_ID,
                goal_id=goal_id,
                command=_cancel(commandId=str(uuid4())),
            )
        )
    assert [issue.code for issue in rejection.value.issues] == ["GOAL_NOT_ACTIVE"]


def test_goals_are_listed_nearest_deadline_first() -> None:
    """Primary-goal order: the deadline that actually needs attention."""

    repository = _FakeRepository(context=_context())
    core = GoalCore(repository=repository, clock=_clock)
    for index, target_on in enumerate(("2027-06-01", "2026-09-01", "2028-01-01")):
        asyncio.run(
            core.create(
                user_id=_USER_ID,
                command=_command(commandId=str(uuid4()), targetOn=target_on),
            )
        )
        del index
    listed = asyncio.run(core.list_goals(user_id=_USER_ID))
    assert [goal.target_on for goal in listed.goals] == [
        date(2026, 9, 1),
        date(2027, 6, 1),
        date(2028, 1, 1),
    ]
    assert listed.evaluated_on == date(2026, 8, 11)


# --- privacy and transport -------------------------------------------------


def test_outbox_payload_carries_identifiers_only() -> None:
    payload = _outbox_payload(
        goal_id=_GOAL_ID,
        user_id=_USER_ID,
        command_id=_COMMAND_ID,
    )
    assert payload == {
        "schemaVersion": "1",
        "goalId": str(_GOAL_ID),
        "userId": str(_USER_ID),
        "commandId": str(_COMMAND_ID),
    }
    serialized = json.dumps(payload, ensure_ascii=False)
    assert "Отпуск" not in serialized
    assert "3000" not in serialized


def test_money_crosses_the_api_as_a_decimal_string() -> None:
    async def scenario() -> None:
        repository = _FakeRepository(context=_context())
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            goal_core=GoalCore(repository=repository, clock=_clock),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/goals",
                json=_command().model_dump(mode="json", by_alias=True),
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 201
        body = response.json()["goal"]
        for key in ("targetAmount", "currentAmount", "progressPercent"):
            assert isinstance(body[key], str)
        assert body["currentAmount"] == "0"
        assert body["achieved"] is False

    asyncio.run(scenario())


def test_an_unavailable_store_is_redacted_to_a_typed_code() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/goals",
                json=_command().model_dump(mode="json", by_alias=True),
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 503
        assert response.json() == {
            "detail": {"code": "GOAL_PERSISTENCE_UNAVAILABLE", "issues": []}
        }
        assert "Отпуск" not in response.text

    asyncio.run(scenario())


def test_malformed_body_is_redacted_to_a_typed_code() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/goals",
                json={"schemaVersion": "1", "title": "Отпуск"},
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 422
        assert response.json() == {
            "detail": {"code": "MALFORMED_GOAL_COMMAND", "issues": []}
        }
        assert "Отпуск" not in response.text

    asyncio.run(scenario())


def test_goals_require_authentication() -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/goals")
        assert response.status_code == 401

    asyncio.run(scenario())


def test_checked_in_goal_contract_is_reproducible() -> None:
    repository_root = Path(__file__).resolve().parents[3]
    checked_in = json.loads(
        (repository_root / "contracts/finance/v1/goal.schema.json").read_text(
            encoding="utf-8"
        )
    )
    assert checked_in == goal_contract_schema()


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(
            subject=str(_USER_ID),
            display_name="Synthetic User",
        )


class _FakeRepository:
    """In-memory stand-in that mirrors the PostgreSQL adapter's contract."""

    def __init__(
        self,
        *,
        context: GoalAccountContext | None = None,
        forced_user_id: UUID | None = None,
        stale_balance: Decimal | None = None,
    ) -> None:
        self._context = context
        self._forced_user_id = forced_user_id
        # Simulates a balance the core saw before another writer moved it, so a
        # racing withdrawal is only stopped by the locked re-check.
        self._stale_balance = stale_balance
        self._goals: dict[UUID, StoredGoal] = {}
        self._ledger: dict[UUID, list[StoredGoalContribution]] = {}
        self._create_hashes: dict[UUID, bytes] = {}
        self._goal_hashes: dict[tuple[UUID, UUID], bytes] = {}
        self._entry_hashes: dict[tuple[UUID, UUID], bytes] = {}
        self._entries_by_command: dict[
            tuple[UUID, UUID],
            StoredGoalContribution,
        ] = {}
        self.writes = 0
        self.contributions = 0

    def _balance(self, goal_id: UUID) -> Decimal:
        total = Decimal(0)
        for entry in self._ledger.get(goal_id, []):
            total = apply_contribution(
                current=total,
                direction=entry.direction,
                amount=entry.amount,
            )
        return total

    def _with_balance(self, goal: StoredGoal) -> StoredGoal:
        balance = self._balance(goal.goal_id)
        return StoredGoal(
            goal_id=goal.goal_id,
            user_id=goal.user_id,
            account_id=goal.account_id,
            command_id=goal.command_id,
            title=goal.title,
            target_amount=goal.target_amount,
            monthly_contribution=goal.monthly_contribution,
            current_amount=balance,
            currency=goal.currency,
            target_on=goal.target_on,
            status=goal.status,
            created_at=goal.created_at,
            updated_at=goal.updated_at,
            canonical_timezone=goal.canonical_timezone,
        )

    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> GoalAccountContext | None:
        del user_id, account_id
        return self._context

    async def get_goal_context(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> tuple[StoredGoal, GoalAccountContext] | None:
        del user_id
        goal = self._goals.get(goal_id)
        if goal is None or self._context is None:
            return None
        stored = self._with_balance(goal)
        if self._stale_balance is not None:
            stored = StoredGoal(
                **{
                    **{
                        field: getattr(stored, field)
                        for field in StoredGoal.__slots__
                        if field != "current_amount"
                    },
                    "current_amount": self._stale_balance,
                }
            )
        return stored, self._context

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> GoalWriteResult | None:
        del user_id
        stored_hash = self._create_hashes.get(command_id)
        if stored_hash is None:
            return None
        if stored_hash != payload_hash:
            raise GoalCommandConflict
        goal = next(
            goal for goal in self._goals.values() if goal.command_id == command_id
        )
        return GoalWriteResult(goal=self._with_balance(goal), idempotent_replay=True)

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreateGoalCommand,
        payload_hash: bytes,
    ) -> GoalWriteResult:
        assert self._context is not None
        self.writes += 1
        goal_id = uuid4()
        goal = StoredGoal(
            goal_id=goal_id,
            user_id=self._forced_user_id or user_id,
            account_id=command.account_id,
            command_id=command.command_id,
            title=command.title,
            target_amount=command.target_amount,
            monthly_contribution=(
                command.monthly_contribution
                if command.monthly_contribution is not None
                else Decimal(0)
            ),
            current_amount=Decimal(0),
            currency=command.currency,
            target_on=command.target_on,
            status="active",
            created_at=_NOW,
            updated_at=_NOW,
            canonical_timezone=self._context.canonical_timezone,
        )
        self._goals[goal_id] = goal
        self._ledger[goal_id] = []
        self._create_hashes[command.command_id] = payload_hash
        return GoalWriteResult(goal=goal, idempotent_replay=False)

    async def replay_existing_goal_command(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> GoalWriteResult | None:
        del user_id
        stored_hash = self._goal_hashes.get((goal_id, command_id))
        if stored_hash is None:
            return None
        if stored_hash != payload_hash:
            raise GoalCommandConflict
        return GoalWriteResult(
            goal=self._with_balance(self._goals[goal_id]),
            idempotent_replay=True,
        )

    async def cancel(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: CancelGoalCommand,
        payload_hash: bytes,
    ) -> GoalWriteResult:
        del user_id
        goal = self._goals.get(goal_id)
        if goal is None:
            raise GoalNotFound
        if goal.status != "active":
            raise GoalNotActive
        cancelled = StoredGoal(
            **{
                **{
                    field: getattr(goal, field)
                    for field in StoredGoal.__slots__
                    if field not in {"status", "updated_at"}
                },
                "status": "cancelled",
                "updated_at": _NOW,
            }
        )
        self._goals[goal_id] = cancelled
        self._goal_hashes[(goal_id, command.command_id)] = payload_hash
        return GoalWriteResult(
            goal=self._with_balance(cancelled),
            idempotent_replay=False,
        )

    async def replay_existing_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> ContributionWriteResult | None:
        del user_id
        stored_hash = self._entry_hashes.get((goal_id, command_id))
        if stored_hash is None:
            return None
        if stored_hash != payload_hash:
            raise GoalCommandConflict
        return ContributionWriteResult(
            contribution=self._entries_by_command[(goal_id, command_id)],
            goal=self._with_balance(self._goals[goal_id]),
            idempotent_replay=True,
        )

    async def record_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: RecordGoalContributionCommand,
        occurred_on: date,
        payload_hash: bytes,
    ) -> ContributionWriteResult:
        goal = self._goals.get(goal_id)
        if goal is None:
            raise GoalNotFound
        if goal.status != "active":
            raise GoalNotActive
        # The authoritative re-check, standing in for the row lock.
        if command.direction == "withdrawal" and command.amount > self._balance(
            goal_id
        ):
            raise GoalWithdrawalExceedsBalance
        self.contributions += 1
        entry = StoredGoalContribution(
            contribution_id=uuid4(),
            goal_id=goal_id,
            user_id=user_id,
            command_id=command.command_id,
            direction=command.direction,
            amount=command.amount,
            currency=goal.currency,
            occurred_on=occurred_on,
            created_at=_NOW,
        )
        self._ledger[goal_id].append(entry)
        self._entry_hashes[(goal_id, command.command_id)] = payload_hash
        self._entries_by_command[(goal_id, command.command_id)] = entry
        return ContributionWriteResult(
            contribution=entry,
            goal=self._with_balance(goal),
            idempotent_replay=False,
        )

    async def list_goals(self, *, user_id: UUID) -> GoalListSnapshot:
        del user_id
        ordered = sorted(
            self._goals.values(),
            key=lambda goal: (goal.target_on, goal.created_at, goal.goal_id),
        )
        return GoalListSnapshot(
            canonical_timezone=(
                self._context.canonical_timezone if self._context else None
            ),
            goals=tuple(self._with_balance(goal) for goal in ordered),
        )

    async def list_contributions(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> GoalLedgerSnapshot:
        del user_id
        goal = self._goals.get(goal_id)
        if goal is None:
            raise GoalNotFound
        return GoalLedgerSnapshot(
            goal=self._with_balance(goal),
            contributions=tuple(self._ledger.get(goal_id, [])),
        )
