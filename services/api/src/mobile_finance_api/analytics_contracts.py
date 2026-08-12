"""Strict versioned contract for the analytics read.

Money crosses as a decimal string, exactly as it does on Home, so the two
screens format the same value the same way.
"""

from __future__ import annotations

from datetime import date
from typing import Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .models import DecimalString, UtcTimestamp


class AnalyticsApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class AnalyticsPeriod(AnalyticsApiModel):
    """The local month analysed, in the account's canonical timezone."""

    start: date = Field(alias="from")
    end: date = Field(alias="to")

    @model_validator(mode="after")
    def start_precedes_end(self) -> Self:
        if self.start > self.end:
            raise ValueError("period start must not follow its end")
        return self


class AnalyticsTotals(AnalyticsApiModel):
    income: DecimalString
    expense: DecimalString
    net_flow: DecimalString = Field(alias="netFlow")

    @model_validator(mode="after")
    def flow_is_the_difference(self) -> Self:
        # Sent rather than left to the client, and checked here so a wrong
        # figure fails closed instead of being rendered.
        if self.net_flow != self.income - self.expense:
            raise ValueError("net flow must equal income minus expense")
        return self


class AnalyticsCategoryTotal(AnalyticsApiModel):
    """What one category accounts for in the period."""

    # Null for operations carrying no link. Uncategorized is its own line
    # rather than hidden or guessed at (ADR 0020), and the client labels it.
    category_id: UUID | None = Field(alias="categoryId")
    name: str | None = Field(max_length=100)
    amount: DecimalString
    share_percent: DecimalString = Field(alias="sharePercent")

    @model_validator(mode="after")
    def an_unlinked_total_has_no_name(self) -> Self:
        if (self.category_id is None) != (self.name is None):
            raise ValueError(
                "a category total has an identifier and a name, or neither"
            )
        if self.amount <= 0:
            raise ValueError("a reported category total must be positive")
        return self


class AnalyticsTrendPoint(AnalyticsApiModel):
    date: date
    amount: DecimalString


class AnalyticsTrend(AnalyticsApiModel):
    metric: Literal["expense"] = "expense"
    period: Literal["7d"] = "7d"
    total: DecimalString
    points: tuple[AnalyticsTrendPoint, ...]

    @model_validator(mode="after")
    def the_series_covers_its_window(self) -> Self:
        if len(self.points) != 7:
            raise ValueError("a 7d trend carries exactly seven points")
        if self.total != sum(
            (point.amount for point in self.points), start=type(self.total)(0)
        ):
            raise ValueError("trend total must equal the sum of its points")
        return self


class AnalyticsResponse(AnalyticsApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    generated_at: UtcTimestamp = Field(alias="generatedAt")
    base_currency: str = Field(alias="baseCurrency", pattern=r"^[A-Z]{3}$")
    period: AnalyticsPeriod
    totals: AnalyticsTotals

    # Ordered largest first. Only categories with something in the period are
    # present: a catalogue can hold dozens of unused ones, and a list of
    # zeroes buries the few lines that say anything.
    expense_by_category: tuple[AnalyticsCategoryTotal, ...] = Field(
        alias="expenseByCategory"
    )
    income_by_category: tuple[AnalyticsCategoryTotal, ...] = Field(
        alias="incomeByCategory"
    )
    trend: AnalyticsTrend

    @model_validator(mode="after")
    def breakdowns_agree_with_their_totals(self) -> Self:
        for reported, breakdown in (
            (self.totals.expense, self.expense_by_category),
            (self.totals.income, self.income_by_category),
        ):
            grouped = sum(
                (item.amount for item in breakdown),
                start=type(reported)(0),
            )
            # A breakdown that does not add up to its own total is the one
            # thing a spending report must never show.
            if grouped != reported:
                raise ValueError("a breakdown must sum to its reported total")
        for breakdown in (self.expense_by_category, self.income_by_category):
            keys = [item.category_id for item in breakdown]
            if len(keys) != len(set(keys)):
                raise ValueError("a category appears at most once per direction")
        return self


AnalyticsErrorCode = Literal[
    "MALFORMED_ANALYTICS_QUERY",
    "ANALYTICS_UNAVAILABLE",
]


class AnalyticsErrorDetail(AnalyticsApiModel):
    code: AnalyticsErrorCode


class AnalyticsErrorResponse(AnalyticsApiModel):
    detail: AnalyticsErrorDetail
