"""Regenerate the checked-in category catalogue v1 JSON Schema."""

from __future__ import annotations

import json
from pathlib import Path

from mobile_finance_api.category_contracts import category_contract_schema


def main() -> None:
    repository_root = Path(__file__).resolve().parents[3]
    destination = repository_root / "contracts/finance/v1/category.schema.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(category_contract_schema(), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
