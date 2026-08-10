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
from mobile_finance_api.main import create_app
from mobile_finance_api.planned_cost_contracts import (
    CreatePlannedCostCommand,
    PlannedCost,
    PlannedCostStatus,
    TransitionPlannedCostCommand,
    create_planned_cost_command_hash,
    derive_is_due,
    planned_cost_contract_schema,
    transition_planned_cost_command_hash,
    transition_target_status,
)
from mobile_finance_api.planned_cost_core import (
    PlannedCostAccountContext,
    PlannedCostCommandConflict,
    PlannedCostConfirmingOperationMissing,
    PlannedCostCore,
    PlannedCostInvalidTransition,
    PlannedCostListSnapshot,
    PlannedCostNotFound,
    PlannedCostPersistenceUnavailable,
    PlannedCostRejected,
    PlannedCostWriteResult,
    StoredPlannedCost,
)
from mobile_finance_api.postgres_planned_cost_repository import _outbox_payload

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_OTHER_USER_ID = UUID("22222222-2222-4222-8222-222222222222")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")
_PLAN_ID = UUID("55555555-5555-4555-8555-555555555555")
_OPERATION_ID = UUID("66666666-6666-4666-8666-666666666666")
_NOW = datetime(2026, 8, 10, 12, 0, tzinfo=UTC)
_TIMEZONE = "Europe/Berlin"


def _clock() -> datetime:
    return _NOW


def _command(**changes: object) -> CreatePlannedCostCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": "44444444-4444-4444-8444-444444444444",
        "accountId": str(_ACCOUNT_ID),
        "amount": "800.00",
        "currency": "EUR",
        "title": "Аренда",
        "category": "Жильё",
        "plannedOn": "2026-09-01",
        "requestedAt": "2026-08-10T12:00:00Z",
    }
    payload.update(changes)
    return CreatePlannedCostCommand.model_validate(payload)


def _transition(**changes: object) -> TransitionPlannedCostCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": "77777777-7777-4777-8777-777777777777",
        "transition": "cancel",
        "requestedAt": "2026-08-10T12:00:00Z",
    }
    payload.update(changes)
    return TransitionPlannedCostCommand.model_validate(payload)


def _context(
    *,
    currency: str = "EUR",
    opening_balance_on: date = date(2026, 1, 1),
) -> PlannedCostAccountContext:
    return PlannedCostAccountContext(
        account_id=_ACCOUNT_ID,
        user_id=_USER_ID,
        currency=currency,
        opening_balance_on=opening_balance_on,
        canonical_timezone=_TIMEZONE,
    )


def _stored(
    *,
    status: str = "planned",
    planned_on: date = date(2026, 9, 1),
    user_id: UUID = _USER_ID,
    confirmed_operation_id: UUID | None = None,
    canonical_timezone: str = _TIMEZONE,
) -> StoredPlannedCost:
    return StoredPlannedCost(
        planned_cost_id=_PLAN_ID,
        user_id=user_id,
        account_id=_ACCOUNT_ID,
        command_id=UUID("44444444-4444-4444-8444-444444444444"),
        amount=Decimal("800.00"),
        currency="EUR",
        title="Аренда",
        category="Жильё",
        planned_on=planned_on,
        status=status,
        confirmed_operation_id=confirmed_operation_id,
        created_at=_NOW,
        updated_at=_NOW,
        canonical_timezone=canonical_timezone,
    )


# --- contract rules --------------------------------------------------------


@pytest.mark.parametrize(
    "amount",
    [0, 800.0, "0", "0.0", "-1", "1e2", "NaN", "Infinity"],
)
def test_amount_requires_a_positive_plain_decimal_string(amount: object) -> None:
    with pytest.raises(ValidationError):
        _command(amount=amount)


def test_contract_rejects_mass_assignment_and_naive_time() -> None:
    with pytest.raises(ValidationError):
        _command(userId=str(uuid4()))
    with pytest.raises(ValidationError):
        _command(plannedCostId=str(uuid4()))
    with pytest.raises(ValidationError):
        _command(requestedAt="2026-08-10T12:00:00")


def test_title_is_required_and_control_characters_are_refused() -> None:
    with pytest.raises(ValidationError):
        _command(title="")
    with pytest.raises(ValidationError):
        _command(title=None)
    with pytest.raises(ValidationError):
        _command(title="Аренда\u0007")
    with pytest.raises(ValidationError):
        _command(category="Жильё\u0000")
    assert _command(title="  Аренда  ").title == "Аренда"
    with pytest.raises(ValidationError):
        _command(title="А" * 101)


def test_confirmation_must_carry_its_operation_and_others_must_not() -> None:
    with pytest.raises(ValidationError):
        _transition(transition="confirm")
    with pytest.raises(ValidationError):
        _transition(transition="skip", operationCommandId=str(uuid4()))
    confirmed = _transition(
        transition="confirm",
        operationCommandId=str(_OPERATION_ID),
    )
    assert confirmed.operation_command_id == _OPERATION_ID


def test_transition_maps_to_exactly_one_terminal_status() -> None:
    assert transition_target_status("confirm") == "confirmed"
    assert transition_target_status("skip") == "skipped"
    assert transition_target_status("cancel") == "cancelled"


def test_planned_cost_view_rejects_inconsistent_lifecycle() -> None:
    base: dict[str, object] = {
        "plannedCostId": str(_PLAN_ID),
        "userId": str(_USER_ID),
        "accountId": str(_ACCOUNT_ID),
        "commandId": str(uuid4()),
        "amount": "800.00",
        "currency": "EUR",
        "title": "Аренда",
        "category": None,
        "plannedOn": "2026-09-01",
        "status": "planned",
        "isDue": False,
        "confirmedOperationId": None,
        "createdAt": "2026-08-10T12:00:00Z",
        "updatedAt": "2026-08-10T12:00:00Z",
    }
    assert PlannedCost.model_validate(base).status == "planned"
    # A settled plan can never still be "due".
    with pytest.raises(ValidationError):
        PlannedCost.model_validate({**base, "status": "cancelled", "isDue": True})
    # Confirmed status and the operation link must agree in both directions.
    with pytest.raises(ValidationError):
        PlannedCost.model_validate({**base, "status": "confirmed"})
    with pytest.raises(ValidationError):
        PlannedCost.model_validate({**base, "confirmedOperationId": str(_OPERATION_ID)})
    with pytest.raises(ValidationError):
        PlannedCost.model_validate({**base, "updatedAt": "2026-08-10T11:59:00Z"})


def test_create_hash_covers_every_field_of_the_command() -> None:
    baseline = create_planned_cost_command_hash(_command())
    assert baseline == create_planned_cost_command_hash(_command())
    for change in (
        {"amount": "800.01"},
        {"plannedOn": "2026-09-02"},
        {"title": "Аренда гаража"},
        {"category": None},
        {"requestedAt": "2026-08-10T12:00:01Z"},
    ):
        assert create_planned_cost_command_hash(_command(**change)) != baseline


def test_transition_hash_binds_the_command_to_one_plan() -> None:
    command = _transition()
    first = transition_planned_cost_command_hash(
        planned_cost_id=_PLAN_ID,
        command=command,
    )
    other = transition_planned_cost_command_hash(
        planned_cost_id=uuid4(),
        command=command,
    )
    assert first != other
    assert first == transition_planned_cost_command_hash(
        planned_cost_id=_PLAN_ID,
        command=_transition(),
    )


def test_due_is_derived_in_the_account_timezone_not_utc() -> None:
    # 2026-08-10T20:00Z is already 2026-08-11 in Auckland, so a plan for the
    # 11th is due locally while the UTC calendar date still reads the 10th.
    core = PlannedCostCore(
        repository=_FakeRepository(),
        clock=lambda: datetime(2026, 8, 10, 20, 0, tzinfo=UTC),
    )
    contract = core._to_contract(
        _stored(planned_on=date(2026, 8, 11), canonical_timezone="Pacific/Auckland")
    )
    assert contract.is_due is True

    utc_view = core._to_contract(
        _stored(planned_on=date(2026, 8, 11), canonical_timezone="UTC")
    )
    assert utc_view.is_due is False


def test_derive_is_due_only_applies_to_outstanding_plans() -> None:
    today = date(2026, 9, 1)
    assert derive_is_due(planned_on=today, status="planned", today_local=today) is True
    assert (
        derive_is_due(planned_on=date(2026, 8, 1), status="planned", today_local=today)
        is True
    )
    assert (
        derive_is_due(planned_on=date(2026, 9, 2), status="planned", today_local=today)
        is False
    )
    for settled in ("confirmed", "skipped", "cancelled"):
        assert (
            derive_is_due(planned_on=today, status=settled, today_local=today) is False
        )


# --- creation rules --------------------------------------------------------


def test_a_future_planned_date_is_accepted() -> None:
    """The whole point of the entity: forecasts live in the future."""

    repository = _FakeRepository(context=_context())
    core = PlannedCostCore(repository=repository, clock=_clock)
    response = asyncio.run(
        core.create(user_id=_USER_ID, command=_command(plannedOn="2027-12-31"))
    )
    assert response.planned_cost.planned_on == date(2027, 12, 31)
    assert response.planned_cost.status == "planned"
    assert response.planned_cost.is_due is False
    assert response.idempotent_replay is False


def test_a_past_planned_date_is_accepted_and_reads_as_due() -> None:
    repository = _FakeRepository(context=_context())
    core = PlannedCostCore(repository=repository, clock=_clock)
    response = asyncio.run(
        core.create(user_id=_USER_ID, command=_command(plannedOn="2026-08-01"))
    )
    assert response.planned_cost.is_due is True


@pytest.mark.parametrize(
    ("changes", "context", "expected"),
    [
        ({}, None, ("ACCOUNT_UNAVAILABLE", "accountId")),
        (
            {},
            _context(currency="USD"),
            ("ACCOUNT_CURRENCY_MISMATCH", "currency"),
        ),
        (
            {"currency": "USD"},
            _context(currency="USD"),
            ("UNSUPPORTED_CURRENCY", "currency"),
        ),
        (
            {"plannedOn": "2025-12-31"},
            _context(opening_balance_on=date(2026, 1, 1)),
            ("PLAN_BEFORE_ACCOUNT_BASELINE", "plannedOn"),
        ),
    ],
)
def test_creation_is_rejected_deterministically(
    changes: dict[str, object],
    context: PlannedCostAccountContext | None,
    expected: tuple[str, str],
) -> None:
    repository = _FakeRepository(context=context)
    core = PlannedCostCore(repository=repository, clock=_clock)
    with pytest.raises(PlannedCostRejected) as rejection:
        asyncio.run(core.create(user_id=_USER_ID, command=_command(**changes)))
    codes = [(issue.code, issue.field) for issue in rejection.value.issues]
    assert expected in codes
    assert repository.writes == 0


def test_exact_replay_returns_the_original_and_writes_nothing() -> None:
    repository = _FakeRepository(context=_context())
    core = PlannedCostCore(repository=repository, clock=_clock)
    first = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    assert first.idempotent_replay is False
    assert repository.writes == 1

    replay = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    assert replay.idempotent_replay is True
    assert replay.planned_cost.planned_cost_id == first.planned_cost.planned_cost_id
    assert repository.writes == 1


def test_same_command_with_different_content_is_a_conflict() -> None:
    repository = _FakeRepository(context=_context())
    core = PlannedCostCore(repository=repository, clock=_clock)
    asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    with pytest.raises(PlannedCostCommandConflict):
        asyncio.run(core.create(user_id=_USER_ID, command=_command(amount="900.00")))
    assert repository.writes == 1


def test_a_foreign_result_fails_closed() -> None:
    repository = _FakeRepository(context=_context(), forced_user_id=_OTHER_USER_ID)
    core = PlannedCostCore(repository=repository, clock=_clock)
    with pytest.raises(PlannedCostPersistenceUnavailable):
        asyncio.run(core.create(user_id=_USER_ID, command=_command()))


# --- lifecycle rules -------------------------------------------------------


@pytest.mark.parametrize(
    ("transition", "status"),
    [("confirm", "confirmed"), ("skip", "skipped"), ("cancel", "cancelled")],
)
def test_each_transition_settles_the_plan_once(
    transition: str,
    status: str,
) -> None:
    repository = _FakeRepository(context=_context())
    core = PlannedCostCore(repository=repository, clock=_clock)
    created = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    plan_id = created.planned_cost.planned_cost_id
    command = _transition(
        transition=transition,
        **(
            {"operationCommandId": str(_OPERATION_ID)}
            if transition == "confirm"
            else {}
        ),
    )
    response = asyncio.run(
        core.transition(user_id=_USER_ID, planned_cost_id=plan_id, command=command)
    )
    assert response.planned_cost.status == status
    assert response.planned_cost.is_due is False
    assert response.idempotent_replay is False

    # A settled plan has no path back, so a second transition is refused.
    with pytest.raises(PlannedCostRejected) as rejection:
        asyncio.run(
            core.transition(
                user_id=_USER_ID,
                planned_cost_id=plan_id,
                command=_transition(commandId=str(uuid4())),
            )
        )
    assert [issue.code for issue in rejection.value.issues] == [
        "INVALID_LIFECYCLE_TRANSITION"
    ]


def test_confirmation_links_the_operation_that_settled_the_plan() -> None:
    repository = _FakeRepository(context=_context(), operations={_OPERATION_ID})
    core = PlannedCostCore(repository=repository, clock=_clock)
    created = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    response = asyncio.run(
        core.transition(
            user_id=_USER_ID,
            planned_cost_id=created.planned_cost.planned_cost_id,
            command=_transition(
                transition="confirm",
                operationCommandId=str(_OPERATION_ID),
            ),
        )
    )
    assert response.planned_cost.status == "confirmed"
    assert response.planned_cost.confirmed_operation_id is not None


def test_confirmation_fails_closed_without_the_operation() -> None:
    repository = _FakeRepository(context=_context(), operations=set())
    core = PlannedCostCore(repository=repository, clock=_clock)
    created = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    with pytest.raises(PlannedCostRejected) as rejection:
        asyncio.run(
            core.transition(
                user_id=_USER_ID,
                planned_cost_id=created.planned_cost.planned_cost_id,
                command=_transition(
                    transition="confirm",
                    operationCommandId=str(uuid4()),
                ),
            )
        )
    assert [(issue.code, issue.field) for issue in rejection.value.issues] == [
        ("CONFIRMING_OPERATION_MISSING", "operationCommandId")
    ]


def test_transition_replay_returns_the_original_result() -> None:
    repository = _FakeRepository(context=_context())
    core = PlannedCostCore(repository=repository, clock=_clock)
    created = asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    plan_id = created.planned_cost.planned_cost_id
    first = asyncio.run(
        core.transition(
            user_id=_USER_ID,
            planned_cost_id=plan_id,
            command=_transition(),
        )
    )
    replay = asyncio.run(
        core.transition(
            user_id=_USER_ID,
            planned_cost_id=plan_id,
            command=_transition(),
        )
    )
    assert first.idempotent_replay is False
    assert replay.idempotent_replay is True
    assert replay.planned_cost.status == "cancelled"
    assert repository.transitions == 1


def test_listing_reports_the_local_evaluation_date() -> None:
    repository = _FakeRepository(context=_context())
    core = PlannedCostCore(repository=repository, clock=_clock)
    asyncio.run(core.create(user_id=_USER_ID, command=_command()))
    response = asyncio.run(core.list_plans(user_id=_USER_ID))
    assert response.evaluated_on == date(2026, 8, 10)
    assert len(response.planned_costs) == 1
    assert response.planned_costs[0].is_due is False


# --- privacy ---------------------------------------------------------------


def test_outbox_payload_carries_identifiers_only() -> None:
    payload = _outbox_payload(
        planned_cost_id=_PLAN_ID,
        user_id=_USER_ID,
        command_id=_OPERATION_ID,
    )
    assert payload == {
        "schemaVersion": "1",
        "plannedCostId": str(_PLAN_ID),
        "userId": str(_USER_ID),
        "commandId": str(_OPERATION_ID),
    }
    rendered = json.dumps(payload, ensure_ascii=False)
    assert "Аренда" not in rendered
    assert "800" not in rendered


# --- HTTP boundary ---------------------------------------------------------


def test_create_returns_201_then_200_on_replay() -> None:
    async def scenario() -> None:
        core = PlannedCostCore(
            repository=_FakeRepository(context=_context()),
            clock=_clock,
        )
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            planned_cost_core=core,
        )
        body = _command().model_dump(mode="json", by_alias=True)
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            created = await client.post(
                "/api/v1/planned-costs",
                json=body,
                headers={"Authorization": "Bearer synthetic-token"},
            )
            replayed = await client.post(
                "/api/v1/planned-costs",
                json=body,
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert created.status_code == 201
        assert created.json()["idempotentReplay"] is False
        assert created.headers["cache-control"] == "no-store"
        assert replayed.status_code == 200
        assert replayed.json()["idempotentReplay"] is True

    asyncio.run(scenario())


def test_rejection_is_typed_and_never_echoes_financial_intent() -> None:
    async def scenario() -> None:
        core = PlannedCostCore(repository=_FakeRepository(context=None), clock=_clock)
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            planned_cost_core=core,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/planned-costs",
                json=_command().model_dump(mode="json", by_alias=True),
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 422
        assert response.json() == {
            "detail": {
                "code": "PLANNED_COST_REJECTED",
                "issues": [{"code": "ACCOUNT_UNAVAILABLE", "field": "accountId"}],
            }
        }
        assert "Аренда" not in response.text
        assert "800" not in response.text

    asyncio.run(scenario())


def test_unknown_plan_is_a_typed_404() -> None:
    async def scenario() -> None:
        core = PlannedCostCore(
            repository=_FakeRepository(context=_context()),
            clock=_clock,
        )
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            planned_cost_core=core,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                f"/api/v1/planned-costs/{uuid4()}/transition",
                json=_transition().model_dump(mode="json", by_alias=True),
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 404
        assert response.json() == {
            "detail": {"code": "PLANNED_COST_NOT_FOUND", "issues": []}
        }

    asyncio.run(scenario())


def test_unavailable_persistence_is_stable_and_redacted() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/planned-costs",
                json=_command().model_dump(mode="json", by_alias=True),
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 503
        assert response.headers["cache-control"] == "no-store"
        assert response.json() == {
            "detail": {
                "code": "PLANNED_COST_PERSISTENCE_UNAVAILABLE",
                "issues": [],
            }
        }
        assert "Аренда" not in response.text

    asyncio.run(scenario())


def test_malformed_body_is_redacted_to_a_typed_code() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/planned-costs",
                json={"schemaVersion": "1", "title": "Аренда", "amount": "800.00"},
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 422
        assert response.json() == {
            "detail": {"code": "MALFORMED_PLANNED_COST", "issues": []}
        }
        assert "Аренда" not in response.text

    asyncio.run(scenario())


def test_checked_in_planned_cost_contract_is_reproducible() -> None:
    repository_root = Path(__file__).resolve().parents[3]
    checked_in = json.loads(
        (repository_root / "contracts/finance/v1/planned_cost.schema.json").read_text(
            encoding="utf-8"
        )
    )
    assert checked_in == planned_cost_contract_schema()


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
        context: PlannedCostAccountContext | None = None,
        operations: set[UUID] | None = None,
        forced_user_id: UUID | None = None,
    ) -> None:
        self._context = context
        self._operations = operations if operations is not None else {_OPERATION_ID}
        self._forced_user_id = forced_user_id
        self._plans: dict[UUID, StoredPlannedCost] = {}
        self._create_hashes: dict[UUID, bytes] = {}
        self._transition_hashes: dict[tuple[UUID, UUID], bytes] = {}
        self.writes = 0
        self.transitions = 0

    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> PlannedCostAccountContext | None:
        del user_id, account_id
        return self._context

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult | None:
        del user_id
        stored_hash = self._create_hashes.get(command_id)
        if stored_hash is None:
            return None
        if stored_hash != payload_hash:
            raise PlannedCostCommandConflict
        plan = next(
            plan for plan in self._plans.values() if plan.command_id == command_id
        )
        return PlannedCostWriteResult(plan=plan, idempotent_replay=True)

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostCommand,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult:
        assert self._context is not None
        self.writes += 1
        planned_cost_id = uuid4()
        plan = StoredPlannedCost(
            planned_cost_id=planned_cost_id,
            user_id=self._forced_user_id or user_id,
            account_id=command.account_id,
            command_id=command.command_id,
            amount=command.amount,
            currency=command.currency,
            title=command.title,
            category=command.category,
            planned_on=command.planned_on,
            status="planned",
            confirmed_operation_id=None,
            created_at=_NOW,
            updated_at=_NOW,
            canonical_timezone=self._context.canonical_timezone,
        )
        self._plans[planned_cost_id] = plan
        self._create_hashes[command.command_id] = payload_hash
        return PlannedCostWriteResult(plan=plan, idempotent_replay=False)

    async def replay_existing_transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult | None:
        del user_id
        stored_hash = self._transition_hashes.get((planned_cost_id, command_id))
        if stored_hash is None:
            return None
        if stored_hash != payload_hash:
            raise PlannedCostCommandConflict
        return PlannedCostWriteResult(
            plan=self._plans[planned_cost_id],
            idempotent_replay=True,
        )

    async def transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command: TransitionPlannedCostCommand,
        payload_hash: bytes,
        target_status: PlannedCostStatus,
    ) -> PlannedCostWriteResult:
        del user_id
        plan = self._plans.get(planned_cost_id)
        if plan is None:
            raise PlannedCostNotFound
        if plan.status != "planned":
            raise PlannedCostInvalidTransition
        operation_id: UUID | None = None
        if target_status == "confirmed":
            if command.operation_command_id not in self._operations:
                raise PlannedCostConfirmingOperationMissing
            operation_id = _OPERATION_ID
        self.transitions += 1
        settled = StoredPlannedCost(
            planned_cost_id=plan.planned_cost_id,
            user_id=plan.user_id,
            account_id=plan.account_id,
            command_id=plan.command_id,
            amount=plan.amount,
            currency=plan.currency,
            title=plan.title,
            category=plan.category,
            planned_on=plan.planned_on,
            status=target_status,
            confirmed_operation_id=operation_id,
            created_at=plan.created_at,
            updated_at=_NOW,
            canonical_timezone=plan.canonical_timezone,
        )
        self._plans[planned_cost_id] = settled
        self._transition_hashes[(planned_cost_id, command.command_id)] = payload_hash
        return PlannedCostWriteResult(plan=settled, idempotent_replay=False)

    async def list_plans(
        self,
        *,
        user_id: UUID,
        planned_from: date | None,
        planned_to: date | None,
    ) -> PlannedCostListSnapshot:
        del user_id
        plans = [
            plan
            for plan in self._plans.values()
            if (planned_from is None or plan.planned_on >= planned_from)
            and (planned_to is None or plan.planned_on <= planned_to)
        ]
        return PlannedCostListSnapshot(
            canonical_timezone=(
                self._context.canonical_timezone if self._context else None
            ),
            plans=tuple(sorted(plans, key=lambda plan: plan.planned_on)),
        )
