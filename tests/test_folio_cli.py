"""Unit tests for scripts/folio.py: argument parsing and number formatting (no database needed)."""

import importlib.util
import unittest
from datetime import date
from decimal import Decimal
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "folio", Path(__file__).resolve().parent.parent / "scripts" / "folio.py")
folio = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(folio)


class ParserTest(unittest.TestCase):
    """Checks that each command accepts valid input and rejects invalid input."""

    def parse(self, *argv):
        return folio.build_parser().parse_args(list(argv))

    def test_whatif_by_shares(self):
        args = self.parse("whatif", "AAPL", "2015-01-02", "--shares", "10")
        self.assertEqual(args.date, date(2015, 1, 2))
        self.assertEqual(args.shares, Decimal("10"))
        self.assertIsNone(args.amount)
        self.assertEqual(args.currency, "EUR")

    def test_whatif_by_amount_with_end_date(self):
        args = self.parse("whatif", "NVDA", "2016-01-04", "--amount", "1000.50", "--currency", "usd", "--to", "2020-12-31")
        self.assertEqual(args.amount, Decimal("1000.50"))
        self.assertEqual(args.to, date(2020, 12, 31))

    def test_whatif_needs_exactly_one_size(self):
        with self.assertRaises(SystemExit):
            self.parse("whatif", "AAPL", "2015-01-02")
        with self.assertRaises(SystemExit):
            self.parse("whatif", "AAPL", "2015-01-02", "--shares", "1", "--amount", "100")

    def test_rejects_bad_dates_and_numbers(self):
        for argv in (["whatif", "AAPL", "2015-13-01", "--shares", "1"],
                     ["whatif", "AAPL", "2015-01-02", "--shares", "-5"],
                     ["whatif", "AAPL", "2015-01-02", "--amount", "abc"]):
            with self.assertRaises(SystemExit):
                self.parse(*argv)

    def test_compare_defaults_to_1000(self):
        self.assertEqual(self.parse("compare", "2016-01-04").amount, Decimal("1000"))

    def test_portfolio_options(self):
        args = self.parse("portfolio", "--as-of", "2024-12-31", "--history")
        self.assertEqual(args.as_of, date(2024, 12, 31))
        self.assertTrue(args.history)
        self.assertEqual(args.account, "Main")


class FormatTest(unittest.TestCase):
    """Checks how amounts, percentages and share counts are shown."""

    def test_money(self):
        self.assertEqual(folio.money(Decimal("1234.5"), "EUR"), "€1,234.50")
        self.assertEqual(folio.money(Decimal("-20"), "USD"), "-$20.00")
        self.assertEqual(folio.money(Decimal("7"), "CHF"), "7.00 CHF")

    def test_pct_sign_and_colour(self):
        self.assertEqual(folio.pct(Decimal("12.5")), "[green]+12.50%[/]")
        self.assertEqual(folio.pct(Decimal("-3")), "[red]-3.00%[/]")
        self.assertEqual(folio.pct(Decimal("28.7"), signed=False), "[green]28.70%[/]")

    def test_shares_drop_trailing_zeros(self):
        self.assertEqual(folio.shares(Decimal("40.000000")), "40")
        self.assertEqual(folio.shares(Decimal("2.364087")), "2.364087")
        self.assertEqual(folio.shares(Decimal("1250.500000")), "1,250.5")

    def test_missing_values(self):
        self.assertEqual(folio.money(None, "EUR"), "[dim]n/a[/]")
        self.assertEqual(folio.pct(None), "[dim]n/a[/]")


if __name__ == "__main__":
    unittest.main()
