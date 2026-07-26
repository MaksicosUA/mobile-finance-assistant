"""Validated Home v1 API models.

Money remains ``Decimal`` inside the service and is serialized as a JSON
string at the HTTP boundary. Timestamps are normalized to UTC and serialized
with the explicit ``Z`` suffix required by the mobile contract.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Annotated, Any, Literal, Self

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    PlainSerializer,
    StringConstraints,
    WithJsonSchema,
    field_validator,
    model_validator,
)

DECIMAL_PATTERN = r"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$"
CURRENCY_PATTERN = r"^[A-Z]{3}$"


def _finite_decimal(value: Decimal) -> Decimal:
    if not value.is_finite():
        raise ValueError("money and decimal values must be finite")
    return value


def _decimal_string(value: Decimal) -> str:
    return format(value, "f")


def _utc_datetime(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("timestamp must include a timezone")
    return value.astimezone(UTC)


def _utc_timestamp(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


DecimalString = Annotated[
    Decimal,
    Field(strict=True),
    AfterValidator(_finite_decimal),
    PlainSerializer(_decimal_string, return_type=str, when_used="json"),
    WithJsonSchema(
        {"type": "string", "pattern": DECIMAL_PATTERN},
        mode="serialization",
    ),
]
UtcTimestamp = Annotated[
    datetime,
    AfterValidator(_utc_datetime),
    PlainSerializer(_utc_timestamp, return_type=str, when_used="json"),
    WithJsonSchema(
        {"type": "string", "format": "date-time", "pattern": "Z$"},
        mode="serialization",
    ),
]
CurrencyCode = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        min_length=3,
        max_length=3,
        pattern=CURRENCY_PATTERN,
    ),
]
NonEmptyText = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=160),
]
OpaqueId = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=128),
]
OpenEnumValue = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=64),
]


def _additive_schema(schema: dict[str, Any]) -> None:
    schema["additionalProperties"] = True


class ApiModel(BaseModel):
    """Strict immutable base for response models."""

    model_config = ConfigDict(
        extra="forbid",
        frozen=True,
        json_schema_extra=_additive_schema,
        populate_by_name=True,
    )


class HomeState(StrEnum):
    READY = "ready"
    FIRST_USE_EMPTY = "first_use_empty"


OpenHomeState = Annotated[
    HomeState,
    WithJsonSchema(
        {
            "type": "string",
            "minLength": 1,
            "description": (
                "Open enum. Known v1 values: ready, first_use_empty. "
                "first_use_empty contains no financial data or warnings."
            ),
        },
        mode="serialization",
    ),
]
ConfirmedStatus = Annotated[
    Literal["confirmed"],
    WithJsonSchema(
        {
            "type": "string",
            "minLength": 1,
            "description": "Open enum. Home v1 emits confirmed transactions.",
        },
        mode="serialization",
    ),
]


class HomeUser(ApiModel):
    display_name: NonEmptyText = Field(alias="displayName")


class HomeBalance(ApiModel):
    amount: DecimalString
    delta_amount: DecimalString = Field(alias="deltaAmount")
    delta_percent: DecimalString = Field(alias="deltaPercent")


class HomeMonthSummary(ApiModel):
    from_: date = Field(alias="from")
    to: date
    income: DecimalString
    expense: DecimalString
    net_flow: DecimalString = Field(alias="netFlow")

    @model_validator(mode="after")
    def boundaries_are_ordered(self) -> Self:
        if self.to < self.from_:
            raise ValueError("month summary end precedes its start")
        if self.income < 0 or self.expense < 0:
            raise ValueError("month income and expense cannot be negative")
        if self.net_flow != self.income - self.expense:
            raise ValueError("month net flow must equal income minus expense")
        return self


class HomeTrendPoint(ApiModel):
    date: date
    amount: DecimalString


class HomeTrend(ApiModel):
    metric: OpenEnumValue
    period: OpenEnumValue
    total: DecimalString
    points: tuple[HomeTrendPoint, ...] = Field(max_length=30)

    @model_validator(mode="after")
    def expense_values_are_nonnegative(self) -> Self:
        if self.metric == "expense" and (
            self.total < 0 or any(point.amount < 0 for point in self.points)
        ):
            raise ValueError("expense trend values cannot be negative")
        return self


class HomeGoal(ApiModel):
    id: OpaqueId
    title: NonEmptyText
    current: DecimalString
    target: DecimalString
    currency: CurrencyCode
    due_date: date = Field(alias="dueDate")
    progress_percent: DecimalString = Field(alias="progressPercent")
    monthly_contribution: DecimalString = Field(alias="monthlyContribution")

    @model_validator(mode="after")
    def values_are_bounded(self) -> Self:
        if self.current < 0 or self.target <= 0 or self.monthly_contribution < 0:
            raise ValueError("goal amounts are outside supported bounds")
        if not Decimal(0) <= self.progress_percent <= Decimal(100):
            raise ValueError("goal progress must be between 0 and 100")
        return self


class HomePayment(ApiModel):
    id: OpaqueId
    title: NonEmptyText
    due_at: UtcTimestamp = Field(alias="dueAt")
    amount: DecimalString
    currency: CurrencyCode
    status: OpenEnumValue

    @model_validator(mode="after")
    def amount_is_nonnegative(self) -> Self:
        if self.amount < 0:
            raise ValueError("upcoming payment amount cannot be negative")
        return self


class HomeTransaction(ApiModel):
    id: OpaqueId
    title: NonEmptyText
    category: NonEmptyText
    occurred_at: UtcTimestamp = Field(alias="occurredAt")
    amount: DecimalString
    currency: CurrencyCode
    direction: OpenEnumValue
    status: ConfirmedStatus

    @model_validator(mode="after")
    def amount_matches_known_direction(self) -> Self:
        if self.direction == "income" and self.amount < 0:
            raise ValueError("income transaction amount cannot be negative")
        if self.direction == "expense" and self.amount > 0:
            raise ValueError("expense transaction amount cannot be positive")
        return self


class HomeWarning(ApiModel):
    code: OpenEnumValue
    block: OpenEnumValue


class HomeResponse(ApiModel):
    generated_at: UtcTimestamp = Field(alias="generatedAt")
    data_as_of: UtcTimestamp = Field(alias="dataAsOf")
    base_currency: CurrencyCode = Field(alias="baseCurrency")
    home_state: OpenHomeState = Field(default=HomeState.READY, alias="homeState")
    user: HomeUser
    balance: HomeBalance
    month_summary: HomeMonthSummary = Field(alias="monthSummary")
    trend: HomeTrend
    primary_goal: HomeGoal | None = Field(alias="primaryGoal")
    upcoming_payments: tuple[HomePayment, ...] = Field(
        alias="upcomingPayments",
        max_length=3,
    )
    recent_transactions: tuple[HomeTransaction, ...] = Field(
        alias="recentTransactions",
        max_length=3,
    )
    available_actions: tuple[OpenEnumValue, ...] = Field(alias="availableActions")
    warnings: tuple[HomeWarning, ...] = Field(default_factory=tuple, max_length=16)

    @field_validator("available_actions")
    @classmethod
    def actions_are_unique(
        cls,
        value: tuple[OpenEnumValue, ...],
    ) -> tuple[OpenEnumValue, ...]:
        if len(value) != len(set(value)):
            raise ValueError("available actions must be unique")
        return value

    @model_validator(mode="after")
    def timestamps_and_state_are_consistent(self) -> Self:
        if self.data_as_of > self.generated_at:
            raise ValueError("dataAsOf cannot be later than generatedAt")
        if self.home_state is HomeState.FIRST_USE_EMPTY:
            monetary_values = (
                self.balance.amount,
                self.balance.delta_amount,
                self.balance.delta_percent,
                self.month_summary.income,
                self.month_summary.expense,
                self.month_summary.net_flow,
                self.trend.total,
            )
            if (
                any(value != 0 for value in monetary_values)
                or self.trend.points
                or self.primary_goal is not None
                or self.upcoming_payments
                or self.recent_transactions
                or self.warnings
            ):
                raise ValueError(
                    "first-use empty responses cannot contain financial data "
                    "or partial warnings"
                )
        return self
