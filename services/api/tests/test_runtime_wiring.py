"""The production entrypoint must wire every adapter its routes read.

This exists because a wiring mistake reached a device with the whole suite
green: `runtime.py` built the operation repository inside Finance Core and
never passed it to `create_app`, so reading operations answered 503 while
writing them worked. Every test passed its adapter explicitly, so nothing
looked at the one assembly that ships.

Importing `runtime` needs configuration but no database — `create_database`
opens no connection eagerly — so this check is cheap and runs in CI.
"""

from __future__ import annotations

import importlib
import os
import sys
from collections.abc import Iterator

import pytest

_UNAVAILABLE_MARKER = "Unavailable"


@pytest.fixture
def runtime_app() -> Iterator[object]:
    previous = {
        key: os.environ.get(key)
        for key in (
            "MFA_DATABASE_URL",
            "MFA_AUTH_JWT_SECRET",
            "MFA_AUTH_JWT_ISSUER",
            "MFA_AUTH_JWT_AUDIENCE",
        )
    }
    os.environ["MFA_DATABASE_URL"] = (
        "postgresql+asyncpg://synthetic:synthetic@127.0.0.1:1/synthetic"
    )
    os.environ["MFA_AUTH_JWT_SECRET"] = "synthetic-runtime-wiring-secret-32-bytes!!"
    os.environ.setdefault("MFA_AUTH_JWT_ISSUER", "mfa-test")
    os.environ.setdefault("MFA_AUTH_JWT_AUDIENCE", "mfa-test-clients")
    sys.modules.pop("mobile_finance_api.runtime", None)
    try:
        module = importlib.import_module("mobile_finance_api.runtime")
        yield module.app
    finally:
        sys.modules.pop("mobile_finance_api.runtime", None)
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def test_no_route_dependency_is_left_as_an_unavailable_stub(runtime_app) -> None:  # type: ignore[no-untyped-def]
    """Every adapter on app.state must be a real one.

    A stub here is not a crash: it answers 503 forever while the rest of the
    application looks healthy, which is exactly how the last one shipped.
    """

    # Starlette keeps the values in a private dict; there is no public way to
    # enumerate them, and enumerating is the whole point of this check.
    stubbed = {
        name: type(value).__name__
        for name, value in runtime_app.state._state.items()
        if _UNAVAILABLE_MARKER in type(value).__name__
    }
    assert stubbed == {}, stubbed


def test_the_adapters_the_read_routes_need_are_present(runtime_app) -> None:  # type: ignore[no-untyped-def]
    """Named explicitly, so deleting a wire fails here rather than on a phone."""

    state = runtime_app.state._state
    for required in (
        "home_repository",
        "current_user_authenticator",
        "authentication_service",
        "account_core",
        "finance_core",
        "planned_cost_core",
        "planned_cost_recurrence_core",
        "goal_core",
        "budget_core",
        "transfer_core",
        "category_repository",
        "finance_operation_repository",
        "analytics_repository",
        "profile_repository",
        "account_data_repository",
        "app_release_store",
    ):
        assert required in state, required
        assert state[required] is not None, required
