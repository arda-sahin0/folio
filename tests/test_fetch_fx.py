"""Unit tests for scripts/fetch_fx.py: reshaping the ECB's wide CSV into long rows."""

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "fetch_fx", Path(__file__).resolve().parent.parent / "scripts" / "fetch_fx.py")
fetch_fx = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fetch_fx)

WIDE = (
    "Date,USD,JPY,TRL,\n"
    "2025-01-03,1.0321,162.68,N/A,\n"
    "2004-12-31,1.3621,139.65,1836200,\n"
)


class ToLongTest(unittest.TestCase):
    """Checks that every published rate becomes one (date, currency, rate) row."""

    def test_one_row_per_published_rate(self):
        rows = fetch_fx.to_long(WIDE)
        self.assertEqual(len(rows), 5)
        self.assertIn(["2025-01-03", "USD", "1.0321"], rows)
        self.assertIn(["2004-12-31", "TRL", "1836200"], rows)

    def test_missing_rates_are_skipped(self):
        rows = fetch_fx.to_long(WIDE)
        self.assertNotIn("N/A", [r[2] for r in rows])
        self.assertNotIn(["2025-01-03", "TRL", "N/A"], rows)

    def test_trailing_comma_creates_no_currency(self):
        rows = fetch_fx.to_long(WIDE)
        self.assertEqual({r[1] for r in rows}, {"USD", "JPY", "TRL"})


if __name__ == "__main__":
    unittest.main()
