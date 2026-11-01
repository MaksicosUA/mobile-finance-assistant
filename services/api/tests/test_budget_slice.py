"""Monthly budgets: a ceiling, and what the month has done to it (ADR 0027).

The load-bearing claim is that nothing is stored except the limit. These tests
hold the arithmetic at the contract boundary, so a figure that does not add up
fails closed instead of being drawn.
"""

from __future__ import annotations

import asyncio
from datetime import date
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.budget_contracts import (
    BudgetLine,
    BudgetPeriod,
    BudgetsResponse,
    RemoveBudgetCommand,
    SetBudgetCommand,
    set_budget_command_hash,
)
from mobile_finance_api.budget_core import (
    BudgetAccountContext,
    BudgetAlreadyRemoved,
    BudgetCommandConflict,
    BudgetCore,
    BudgetNotFound,
    BudgetPersistenceUnavailable,
    BudgetRejected,
    BudgetWriteResult,
)
from mobile_finance_api.main import create_app

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("22222222-2222-4222-8222-222222222222")
_CATEGORY_ID = UUID("33333333-3333-4333-8333-333333333333")
_BUDGET_ID = UUID("44444444-4444-4444-8444-444444444444")
_COMMAND_ID = UUID("55555555-5555-4555-8555-555555555555")


def _line(**changes: object) -> BudgetLine:
    """Money is a strict Decimal on the way out and a string only on the wire."""

    payload: dict[str, object] = {
        "budgetId": _BUDGET_ID,
        "categoryId": _CATEGORY_ID,
        "name": "Продукты",
        "limit": Decimal("400.00"),
        "spent": Decimal("250.00"),
        "remaining": Decimal("150.00"),
        "planned": Decimal("100.00"),
        "overspent": False,
    }
    payload.update(
        {
            key: Decimal(value) if isinstance(value, str) and key in _MONEY else value
            for key, value in changes.items()
        }
    )
    return BudgetLine.model_validate(payload)


_MONEY = frozenset({"limit", "spent", "remaining", "planned"})


def _command(**changes: object) -> SetBudgetCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_COMMAND_ID),
        "accountId": str(_ACCOUNT_ID),
        "categoryId": str(_CATEGORY_ID),
        "limit": "400.00",
        "currency": "EUR",
        "requestedAt": "2026-09-01T12:00:00Z",
    }
    payload.update(changes)
    return SetBudgetCommand.model_validate(payload)


def _context(currency: str = "EUR") -> BudgetAccountContext:
    return BudgetAccountContext(
        account_id=_ACCOUNT_ID,
        user_id=_USER_ID,
        currency=currency,
    )


class _Repository:
    def __init__(
        self,
        *,
        context: BudgetAccountContext | None = None,
        category_direction: str | None = "expense",
        replay: BudgetWriteResult | None = None,
        raises: Exception | None = None,
        response: BudgetsResponse | None = None,
    ) -> None:
        self._context = context
        self._category_direction = category_direction
        self._replay = replay
        self._raises = raises
        self._response = response
        self.written: list[SetBudgetCommand] = []
        self.removed: list[UUID] = []

    async def get_account_context(self, *, user_id: UUID):  # type: ignore[no-untyped-def]
        del user_id
        return self._context

    async def get_category_direction(self, *, user_id: UUID, category_id: UUID):  # type: ignore[no-untyped-def]
        del user_id, category_id
        return self._category_direction

    async def replay_existing_set(self, **kwargs: object):  # type: ignore[no-untyped-def]
        del kwargs
        return self._replay

    async def set_budget(self, *, user_id: UUID, command, payload_hash: bytes):  # type: ignore[no-untyped-def]
        del user_id, payload_hash
        if self._raises is not None:
            raise self._raises
        self.written.append(command)
        return BudgetWriteResult(
            budget_id=_BUDGET_ID,
            category_id=command.category_id,
            limit=command.limit,
            idempotent_replay=False,
        )

    async def replay_existing_removal(self, **kwargs: object):  # type: ignore[no-untyped-def]
        del kwargs
        return self._replay

    async def remove_budget(self, *, user_id: UUID, budget_id: UUID, **kwargs: object):  # type: ignore[no-untyped-def]
        del user_id, kwargs
        if self._raises is not None:
            raise self._raises
        self.removed.append(budget_id)
        return BudgetWriteResult(
            budget_id=budget_id,
            category_id=_CATEGORY_ID,
            limit=Decimal("400.00"),
            idempotent_replay=False,
        )

    async def read_budgets(self, *, user_id: UUID) -> BudgetsResponse:
        del user_id
        if self._raises is not None:
            raise self._raises
        assert self._response is not None
        return self._response


def _core(repository: _Repository) -> BudgetCore:
    return BudgetCore(repository=repository)  # type: ignore[arg-type]


# --- the arithmetic, held at the boundary -------------------------------------


def test_a_line_that_does_not_add_up_is_refused() -> None:
    with pytest.raises(ValidationError):
        _line(remaining="200.00")


def test_overspent_must_agree_with_the_remainder() -> None:
    with pytest.raises(ValidationError):
        _line(spent="500.00", remaining="-100.00", overspent=False)


def test_going_over_is_a_negative_remainder_not_a_floor_at_zero() -> None:
    line = _line(spent="500.00", remaining="-100.00", overspent=True)

    assert line.remaining == Decimal("-100.00")


def test_a_ceiling_of_zero_is_not_a_ceiling() -> None:
    with pytest.raises(ValidationError):
        _line(limit="0", spent="0", remaining="0")


def test_the_planned_figure_is_never_folded_into_the_remainder() -> None:
    """400 limit, 250 spent, 100 planned leaves 150 — not 50.

    Mixing a forecast into the number that states fact is the one thing this
    product refuses to do (ADR 0018, ADR 0027).
    """

    line = _line()

    assert line.remaining == Decimal("150.00")
    assert line.planned == Decimal("100.00")


def test_a_named_line_must_carry_its_category() -> None:
    with pytest.raises(ValidationError):
        _line(categoryId=None)
    with pytest.raises(ValidationError):
        _line(name=None)


def test_the_overall_ceiling_carries_no_category() -> None:
    overall = _line(categoryId=None, name=None)
    with pytest.raises(ValidationError):
        BudgetsResponse(
            period=BudgetPeriod(start=date(2026, 9, 1), end=date(2026, 9, 30)),
            currency="EUR",
            overall=_line(),
            categories=(),
        )
    assert overall.category_id is None


def test_a_category_may_appear_once() -> None:
    with pytest.raises(ValidationError):
        BudgetsResponse(
            period=BudgetPeriod(start=date(2026, 9, 1), end=date(2026, 9, 30)),
            currency="EUR",
            overall=None,
            categories=(_line(), _line(budgetId=str(uuid4()))),
        )


def test_an_unknown_key_is_refused_rather_than_ignored() -> None:
    with pytest.raises(ValidationError):
        BudgetLine.model_validate({**_line().model_dump(), "rollover": True})


def test_money_crosses_as_a_string() -> None:
    payload = _line().model_dump(mode="json", by_alias=True)

    assert isinstance(payload["limit"], str)
    assert isinstance(payload["remaining"], str)


def test_the_command_hash_binds_every_field() -> None:
    baseline = set_budget_command_hash(_command())

    assert set_budget_command_hash(_command(limit="500.00")) != baseline
    assert set_budget_command_hash(_command(categoryId=None)) != baseline
    assert set_budget_command_hash(_command()) == baseline


# --- what the core refuses -----------------------------------------------------


def test_a_user_without_an_account_cannot_set_a_ceiling() -> None:
    repository = _Repository(context=None)
    with pytest.raises(BudgetRejected) as rejection:
        asyncio.run(_core(repository).set_budget(user_id=_USER_ID, command=_command()))

    assert [issue.code for issue in rejection.value.issues] == ["ACCOUNT_UNAVAILABLE"]
    assert repository.written == []


def test_a_currency_the_account_does_not_use_is_refused() -> None:
    repository = _Repository(context=_context(currency="USD"))
    with pytest.raises(BudgetRejected) as rejection:
        asyncio.run(_core(repository).set_budget(user_id=_USER_ID, command=_command()))

    assert [issue.code for issue in rejection.value.issues] == [
        "ACCOUNT_CURRENCY_MISMATCH"
    ]


def test_a_ceiling_takes_the_currency_of_its_wallet() -> None:
    """A first wallet may be in anything, so a ceiling may be too (issue 0013)."""

    repository = _Repository(context=_context(currency="USD"))
    asyncio.run(
        _core(repository).set_budget(user_id=_USER_ID, command=_command(currency="USD"))
    )

    assert len(repository.written) == 1


def test_an_income_category_cannot_carry_a_ceiling() -> None:
    """Budgeting income is not a thing anyone means."""

    repository = _Repository(context=_context(), category_direction="income")
    with pytest.raises(BudgetRejected) as rejection:
        asyncio.run(_core(repository).set_budget(user_id=_USER_ID, command=_command()))

    assert [issue.code for issue in rejection.value.issues] == [
        "CATEGORY_DIRECTION_MISMATCH"
    ]


def test_an_unknown_category_is_refused() -> None:
    repository = _Repository(context=_context(), category_direction=None)
    with pytest.raises(BudgetRejected) as rejection:
        asyncio.run(_core(repository).set_budget(user_id=_USER_ID, command=_command()))

    assert [issue.code for issue in rejection.value.issues] == ["CATEGORY_UNAVAILABLE"]


def test_the_overall_ceiling_asks_the_catalogue_nothing() -> None:
    repository = _Repository(context=_context(), category_direction=None)
    result = asyncio.run(
        _core(repository).set_budget(
            user_id=_USER_ID,
            command=_command(categoryId=None),
        )
    )

    assert result.category_id is None


def test_removing_a_ceiling_twice_is_refused() -> None:
    repository = _Repository(raises=BudgetAlreadyRemoved())
    with pytest.raises(BudgetRejected) as rejection:
        asyncio.run(
            _core(repository).remove_budget(
                user_id=_USER_ID,
                budget_id=_BUDGET_ID,
                command=RemoveBudgetCommand.model_validate(
                    {
                        "schemaVersion": "1",
                        "commandId": str(uuid4()),
                        "requestedAt": "2026-09-01T12:00:00Z",
                    }
                ),
            )
        )

    assert [issue.code for issue in rejection.value.issues] == [
        "BUDGET_ALREADY_REMOVED"
    ]


def test_replaying_a_write_returns_the_original() -> None:
    repository = _Repository(
        context=_context(),
        replay=BudgetWriteResult(
            budget_id=_BUDGET_ID,
            category_id=_CATEGORY_ID,
            limit=Decimal("400.00"),
            idempotent_replay=True,
        ),
    )
    result = asyncio.run(
        _core(repository).set_budget(user_id=_USER_ID, command=_command())
    )

    assert result.idempotent_replay is True
    assert repository.written == []


# --- over HTTP -----------------------------------------------------------------


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic")


def _application(core: BudgetCore | None = None):  # type: ignore[no-untyped-def]
    return create_app(
        budget_core=core,
        current_user_authenticator=_StaticAuthenticator(),
    )


async def _call(app: object, method: str, path: str, body: object = None):  # type: ignore[no-untyped-def]
    async with AsyncClient(
        transport=ASGITransport(app=app),  # type: ignore[arg-type]
        base_url="http://test",
    ) as client:
        return await client.request(
            method,
            path,
            json=body,
            headers={"Authorization": "Bearer synthetic"},
        )


def _response() -> BudgetsResponse:
    return BudgetsResponse(
        period=BudgetPeriod(start=date(2026, 9, 1), end=date(2026, 9, 30)),
        currency="EUR",
        overall=_line(
            categoryId=None,
            name=None,
            limit="2000.00",
            spent="900.00",
            remaining="1100.00",
            planned="150.00",
        ),
        categories=(_line(),),
    )


def test_reading_reports_both_ceilings() -> None:
    async def scenario() -> None:
        core = _core(_Repository(response=_response()))
        response = await _call(_application(core), "GET", "/api/v1/budgets")

        assert response.status_code == 200
        payload = response.json()
        assert payload["overall"]["remaining"] == "1100.00"
        assert payload["categories"][0]["planned"] == "100.00"
        assert response.headers["cache-control"] == "no-store"

    asyncio.run(scenario())


def test_setting_a_ceiling_answers_200() -> None:
    async def scenario() -> None:
        core = _core(_Repository(context=_context()))
        response = await _call(
            _application(core),
            "PUT",
            "/api/v1/budgets",
            _command().model_dump(mode="json", by_alias=True),
        )

        assert response.status_code == 200
        # Normalised, but never a JSON float.
        assert Decimal(response.json()["limit"]) == Decimal("400.00")

    asyncio.run(scenario())


def test_a_rejection_is_typed_and_carries_no_amounts() -> None:
    async def scenario() -> None:
        core = _core(_Repository(context=None))
        response = await _call(
            _application(core),
            "PUT",
            "/api/v1/budgets",
            _command(limit="1234.56").model_dump(mode="json", by_alias=True),
        )

        assert response.status_code == 422
        assert "1234.56" not in response.text
        assert response.json()["detail"]["code"] == "BUDGET_REJECTED"

    asyncio.run(scenario())


def test_a_reused_command_with_other_content_is_a_conflict() -> None:
    async def scenario() -> None:
        core = _core(_Repository(context=_context(), raises=BudgetCommandConflict()))
        response = await _call(
            _application(core),
            "PUT",
            "/api/v1/budgets",
            _command().model_dump(mode="json", by_alias=True),
        )

        assert response.status_code == 409

    asyncio.run(scenario())


def test_removing_an_unknown_ceiling_answers_404() -> None:
    async def scenario() -> None:
        core = _core(_Repository(raises=BudgetNotFound()))
        response = await _call(
            _application(core),
            "POST",
            f"/api/v1/budgets/{_BUDGET_ID}/remove",
            {
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "requestedAt": "2026-09-01T12:00:00Z",
            },
        )

        assert response.status_code == 404

    asyncio.run(scenario())


def test_an_unwired_deployment_answers_503() -> None:
    async def scenario() -> None:
        response = await _call(_application(), "GET", "/api/v1/budgets")

        assert response.status_code == 503
        assert response.json()["detail"]["code"] == "BUDGET_PERSISTENCE_UNAVAILABLE"

    asyncio.run(scenario())


def test_an_anonymous_caller_is_refused() -> None:
    async def scenario() -> None:
        app = create_app(budget_core=_core(_Repository(response=_response())))
        async with AsyncClient(
            transport=ASGITransport(app=app),  # type: ignore[arg-type]
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/budgets")

        assert response.status_code == 401

    asyncio.run(scenario())


def test_persistence_failure_is_redacted_to_a_typed_code() -> None:
    async def scenario() -> None:
        core = _core(_Repository(raises=BudgetPersistenceUnavailable()))
        response = await _call(_application(core), "GET", "/api/v1/budgets")

        assert response.status_code == 503

    asyncio.run(scenario())
