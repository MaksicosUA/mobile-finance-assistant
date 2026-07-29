"""Shared wide Decimal context for authoritative financial calculations."""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from decimal import Context, localcontext

_CALCULATION_PRECISION = 80


@contextmanager
def wide_decimal_context() -> Iterator[Context]:
    """Avoid default-context rounding for values backed by NUMERIC(38,18)."""

    with localcontext() as context:
        context.prec = _CALCULATION_PRECISION
        yield context
