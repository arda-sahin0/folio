"""Command-line interface to the Folio warehouse.

Every number is calculated in PostgreSQL (see migrations/013_analytics.sql); this script only
parses arguments, calls the SQL functions and formats the results.

Usage:
    python scripts/folio.py list
    python scripts/folio.py whatif AAPL 2015-01-02 --shares 10
    python scripts/folio.py whatif NVDA 2016-01-04 --amount 1000 [--currency EUR] [--to 2020-12-31]
    python scripts/folio.py compare 2016-01-04 --amount 1000 [--to 2020-12-31]
    python scripts/folio.py portfolio [--account Main] [--as-of 2024-12-31] [--history]
"""

import argparse
import os
import sys
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path

import psycopg
from psycopg.rows import dict_row
from rich import box
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

ROOT = Path(__file__).resolve().parent.parent
SYMBOLS = {"EUR": "€", "USD": "$", "GBP": "£", "JPY": "¥"}

console = Console()


def load_env() -> dict:
    """Read .env into a dict; variables already set in the environment take precedence."""
    env = {}
    path = ROOT / ".env"
    if path.exists():
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                env[key.strip()] = value.strip()
    env.update({k: v for k, v in os.environ.items() if k.startswith("POSTGRES_")})
    return env


class FolioError(Exception):
    """A problem to report to the user as a one-line message."""


def connect() -> psycopg.Connection:
    """Open a read-only, autocommit connection to the database described in .env."""
    env = load_env()
    try:
        return psycopg.connect(
            host=env.get("POSTGRES_HOST", "localhost"),
            port=env.get("POSTGRES_PORT", "5432"),
            user=env.get("POSTGRES_USER", "folio"),
            password=env.get("POSTGRES_PASSWORD", ""),
            dbname=env.get("POSTGRES_DB", "folio"),
            options="-c default_transaction_read_only=on",
            autocommit=True,
            row_factory=dict_row,
            connect_timeout=5,
        )
    except psycopg.OperationalError as exc:
        raise FolioError("Cannot reach the database. Is Docker running? Try: docker compose up -d") from exc


def query(conn: psycopg.Connection, sql: str, params: dict | None = None) -> list[dict]:
    """Run one query and return its rows, turning database errors into readable messages."""
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or {})
            return cur.fetchall()
    except psycopg.errors.UndefinedFunction as exc:
        raise FolioError("The analytics functions are missing. Apply migrations/013_analytics.sql "
                         "(see README, 'Command-line interface').") from exc
    except psycopg.Error as exc:
        raise FolioError(exc.diag.message_primary or str(exc)) from exc


def money(value, currency: str) -> str:
    """Format an amount with its currency symbol, e.g. €1,234.56 or 1,234.56 CHF."""
    if value is None:
        return "[dim]n/a[/]"
    text = f"{abs(value):,.2f}"
    sign = "-" if value < 0 else ""
    symbol = SYMBOLS.get(currency)
    return f"{sign}{symbol}{text}" if symbol else f"{sign}{text} {currency}"


def pct(value, signed: bool = True) -> str:
    """Format a percentage, green when positive and red when negative."""
    if value is None:
        return "[dim]n/a[/]"
    colour = "green" if value > 0 else "red" if value < 0 else "white"
    sign = "+" if signed and value > 0 else ""
    return f"[{colour}]{sign}{value:,.2f}%[/]"


def gain(value, currency: str) -> str:
    """Format a profit or loss with a sign and colour."""
    if value is None:
        return "[dim]n/a[/]"
    colour = "green" if value > 0 else "red" if value < 0 else "white"
    sign = "+" if value > 0 else ""
    return f"[{colour}]{sign}{money(value, currency)}[/]"


def shares(value) -> str:
    """Format a share count without trailing zeros."""
    text = f"{value:,.6f}".rstrip("0").rstrip(".")
    return text or "0"


def iso_date(text: str) -> date:
    """argparse type for YYYY-MM-DD dates."""
    try:
        return date.fromisoformat(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a date (use YYYY-MM-DD): {text}")


def positive_number(text: str) -> Decimal:
    """argparse type for positive decimal numbers."""
    try:
        number = Decimal(text)
    except InvalidOperation:
        raise argparse.ArgumentTypeError(f"not a number: {text}")
    if number <= 0:
        raise argparse.ArgumentTypeError(f"must be positive: {text}")
    return number


def two_column_table(rows: list[tuple[str, str]]) -> Table:
    """A borderless label/value table used inside panels."""
    table = Table(box=None, show_header=False, padding=(0, 2))
    table.add_column(style="dim")
    table.add_column(justify="right")
    for label, value in rows:
        table.add_row(label, value)
    return table


def sectioned_table(sections: list[tuple[str, list[tuple[str, str]]]]) -> Table:
    """A label/value table split into titled sections."""
    table = Table(box=None, show_header=False, padding=(0, 2))
    table.add_column(style="dim", min_width=24)
    table.add_column(justify="right")
    for index, (heading, rows) in enumerate(sections):
        if index:
            table.add_row("", "")
        table.add_row(f"[bold cyan]{heading}[/]", "")
        for label, value in rows:
            table.add_row(f"  {label}", value)
    return table


def cmd_list(conn: psycopg.Connection, args: argparse.Namespace) -> None:
    """Show every security with its price history range and latest close."""
    rows = query(conn, """
        SELECT s.ticker, s.name, s.mic_code, s.currency, s.sector,
               r.first_day, r.last_day, r.bars, lp.close
        FROM securities s
        CROSS JOIN LATERAL (
            SELECT min(p.trade_date) AS first_day, max(p.trade_date) AS last_day, count(*) AS bars
            FROM daily_prices p WHERE p.security_id = s.security_id
        ) r
        LEFT JOIN LATERAL (
            SELECT p.close FROM daily_prices p
            WHERE p.security_id = s.security_id
            ORDER BY p.trade_date DESC LIMIT 1
        ) lp ON true
        ORDER BY s.mic_code, s.ticker
    """)
    table = Table(title="Securities", box=box.SIMPLE_HEAVY)
    for column, justify in [("Ticker", "left"), ("Name", "left"), ("Exchange", "left"), ("Sector", "left"),
                            ("Prices from", "left"), ("to", "left"), ("Bars", "right"), ("Last close", "right")]:
        table.add_column(column, justify=justify)
    for r in rows:
        table.add_row(r["ticker"], r["name"], r["mic_code"], r["sector"] or "",
                      str(r["first_day"] or ""), str(r["last_day"] or ""), f"{r['bars']:,}",
                      money(r["close"], r["currency"]) if r["close"] is not None else "")
    console.print(table)


def cmd_whatif(conn: psycopg.Connection, args: argparse.Namespace) -> None:
    """Simulate one investment and print what it would be worth."""
    rows = query(conn, """
        SELECT * FROM whatif(%(ticker)s, %(start)s, p_shares => %(shares)s, p_amount => %(amount)s,
                             p_amount_currency => %(currency)s, p_end => %(end)s)
    """, {"ticker": args.ticker, "start": args.date, "shares": args.shares, "amount": args.amount,
          "currency": args.currency.upper(), "end": args.to})
    w = rows[0]
    ccy = w["currency"]
    title = f"[bold]{w['name']}[/] ({w['ticker']})  {w['buy_date']} → {w['end_date']}"

    notes = []
    if (w["buy_date"] - args.date).days > 7:
        notes.append(f"No prices until {w['buy_date']}, so the purchase happens then.")
    if args.to and (args.to - w["end_date"]).days > 7:
        notes.append(f"Latest price before {args.to} is from {w['end_date']}.")
    if w["cost_eur"] is None or w["value_eur"] is None:
        notes.append("No ECB rate for part of this period (rates start in 1999), so EUR figures are missing.")

    bought = [
        ("Bought on", str(w["buy_date"])),
        ("Price", money(w["buy_price"], ccy)),
        ("Shares", shares(w["shares_bought"])),
        ("Cost", money(w["cost"], ccy) + ("" if ccy == "EUR" else f"  ({money(w['cost_eur'], 'EUR')})")),
    ]
    held = [
        ("Valued on", str(w["end_date"])),
        ("Price", money(w["end_price"], ccy)),
        ("Splits", "none" if w["split_factor"] == 1 else f"×{shares(w['split_factor'])}"),
        ("Shares now", shares(w["shares_now"])),
        ("Value", money(w["value"], ccy) + ("" if ccy == "EUR" else f"  ({money(w['value_eur'], 'EUR')})")),
        ("Dividends received", money(w["dividends"], ccy)
         + ("" if ccy == "EUR" else f"  ({money(w['dividends_eur'], 'EUR')})")),
    ]
    result = [
        ("Profit", gain(w["profit"], ccy)),
        ("Total return", pct(w["return_pct"])),
    ]
    if ccy != "EUR":
        result += [("Profit in EUR", gain(w["profit_eur"], "EUR")),
                   ("Total return in EUR", pct(w["return_eur_pct"]))]
    result += [
        ("Per year (EUR)", pct(w["annualized_eur_pct"]) + f"  over {w['years']} years"
         if w["annualized_eur_pct"] is not None else f"[dim]n/a[/]  (held {w['years']} years)"),
    ]
    risk = [
        ("Volatility (annualised)", pct(w["volatility_pct"], signed=False)),
        ("Max drawdown", "none" if not w["max_drawdown_pct"]
         else pct(w["max_drawdown_pct"]) + f"  ({w['drawdown_peak']} → {w['drawdown_trough']})"),
        ("Best day", pct(w["best_day_pct"]) + f"  ({w['best_day']})"),
        ("Worst day", pct(w["worst_day_pct"]) + f"  ({w['worst_day']})"),
    ]

    sections = [("Purchase", bought), ("Holding", held), ("Result", result), ("Risk", risk)]
    console.print(Panel(sectioned_table(sections), title=title, border_style="cyan", expand=False))
    for note in notes:
        console.print(f"[yellow]Note:[/] {note}")
    console.print("[dim]Bought at the closing price. Dividends are paid out as cash, not reinvested. "
                  "EUR figures use the ECB rate of each day.[/]")


def cmd_compare(conn: psycopg.Connection, args: argparse.Namespace) -> None:
    """Run the same investment in every security, ranked by return in EUR."""
    tickers = [r["ticker"] for r in query(conn, "SELECT ticker FROM securities ORDER BY ticker")]
    results, skipped = [], []
    for ticker in tickers:
        try:
            w = query(conn, """
                SELECT * FROM whatif(%(ticker)s, %(start)s, p_amount => %(amount)s,
                                     p_amount_currency => %(currency)s, p_end => %(end)s)
            """, {"ticker": ticker, "start": args.date, "amount": args.amount,
                  "currency": args.currency.upper(), "end": args.to})[0]
        except FolioError as exc:
            skipped.append(f"{ticker} ({exc})")
            continue
        if (w["buy_date"] - args.date).days > 7:
            skipped.append(f"{ticker} (no prices until {w['buy_date']})")
            continue
        results.append(w)
    if not results:
        raise FolioError(f"No security could be bought on {args.date}.")

    results.sort(key=lambda w: (w["return_eur_pct"] is None, -(w["return_eur_pct"] or 0)))
    cur = args.currency.upper()
    table = Table(title=f"{money(args.amount, cur)} invested on {args.date}, valued on {results[0]['end_date']}",
                  box=box.SIMPLE_HEAVY)
    for column in ["Ticker", "Bought", "Value (EUR)", "Dividends (EUR)", "Return (EUR)", "Per year", "Max drawdown"]:
        table.add_column(column, justify="left" if column in ("Ticker", "Bought") else "right")
    for w in results:
        table.add_row(w["ticker"], str(w["buy_date"]), money(w["value_eur"], "EUR"),
                      money(w["dividends_eur"], "EUR"), pct(w["return_eur_pct"]),
                      pct(w["annualized_eur_pct"]), pct(w["max_drawdown_pct"]))
    console.print(table)
    for line in skipped:
        console.print(f"[dim]Skipped {line}[/]")


def cmd_portfolio(conn: psycopg.Connection, args: argparse.Namespace) -> None:
    """Show the demo account's holdings, totals and, optionally, its value at each year end."""
    as_of = args.as_of or date.today()
    positions = query(conn, "SELECT * FROM portfolio_positions(%(a)s, %(d)s)", {"a": args.account, "d": as_of})
    summary = query(conn, "SELECT * FROM portfolio_summary(%(a)s, %(d)s)", {"a": args.account, "d": as_of})[0]

    table = Table(title=f"Account '{args.account}' on {as_of}", box=box.SIMPLE_HEAVY)
    for column in ["Ticker", "Shares", "Price", "Value", "Value (EUR)", "Weight",
                   "Bought (EUR)", "Sold (EUR)", "Dividends (EUR)", "Profit (EUR)"]:
        table.add_column(column, justify="left" if column == "Ticker" else "right")
    for p in positions:
        table.add_row(p["ticker"], shares(p["shares"]), money(p["price"], p["currency"]),
                      money(p["value"], p["currency"]), money(p["value_eur"], "EUR"),
                      pct(p["weight_pct"], signed=False), money(p["bought_eur"], "EUR"),
                      money(p["sold_eur"], "EUR"), money(p["dividends_eur"], "EUR"),
                      gain(p["profit_eur"], "EUR"))
    console.print(table)

    s = summary
    rows = [
        ("Paid in", money(s["deposits_eur"], "EUR")),
        ("Taken out", money(s["withdrawals_eur"], "EUR")),
        ("Net invested", money(s["net_invested_eur"], "EUR")),
        ("Fees", money(s["fees_eur"], "EUR")),
        ("Dividends received", money(s["dividends_eur"], "EUR")),
        ("Cash", money(s["cash_eur"], "EUR")),
        ("Holdings", money(s["holdings_eur"], "EUR")),
        ("Total value", f"[bold]{money(s['total_value_eur'], 'EUR')}[/]"),
        ("Profit", gain(s["profit_eur"], "EUR")),
        ("Return on net invested", pct(s["return_pct"])),
    ]
    console.print(Panel(two_column_table(rows), title="Summary (EUR)", border_style="green", expand=False))

    if args.history:
        history = query(conn, """
            SELECT h.*
            FROM (SELECT DISTINCT d::date AS as_of
                  FROM generate_series(
                           (SELECT make_date(extract(year FROM opening_date)::int, 12, 31)
                            FROM accounts WHERE name = %(a)s),
                           %(d)s::date, interval '1 year') d
                  UNION
                  SELECT %(d)s::date) dates
            CROSS JOIN LATERAL portfolio_summary(%(a)s, dates.as_of) h
            ORDER BY h.as_of
        """, {"a": args.account, "d": as_of})
        hist = Table(title="Value at each year end", box=box.SIMPLE_HEAVY)
        for column in ["Date", "Net invested", "Cash", "Holdings", "Total value", "Profit", "Return"]:
            hist.add_column(column, justify="left" if column == "Date" else "right")
        for h in history:
            hist.add_row(str(h["as_of"]), money(h["net_invested_eur"], "EUR"), money(h["cash_eur"], "EUR"),
                         money(h["holdings_eur"], "EUR"), money(h["total_value_eur"], "EUR"),
                         gain(h["profit_eur"], "EUR"), pct(h["return_pct"]))
        console.print(hist)

    console.print("[dim]Each trade, dividend and fee is converted to EUR at the ECB rate of its day. "
                  "Return = profit / net amount paid in (not time-weighted).[/]")


def build_parser() -> argparse.ArgumentParser:
    """Define the commands and their arguments."""
    parser = argparse.ArgumentParser(
        prog="folio",
        description="Query the Folio warehouse: simulate investments and check the demo portfolio.")
    commands = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")

    commands.add_parser("list", help="list the securities and their price history")

    whatif = commands.add_parser("whatif", help="what if I had bought a stock on a given date?")
    whatif.add_argument("ticker", help="e.g. AAPL, SAP, NVDA")
    whatif.add_argument("date", type=iso_date, help="purchase date, YYYY-MM-DD")
    size = whatif.add_mutually_exclusive_group(required=True)
    size.add_argument("--shares", type=positive_number, help="number of shares to buy")
    size.add_argument("--amount", type=positive_number, help="amount of money to invest")
    whatif.add_argument("--currency", default="EUR", help="currency of --amount (default EUR)")
    whatif.add_argument("--to", type=iso_date, help="sell/valuation date (default: latest price)")

    compare = commands.add_parser("compare", help="the same investment in every security, ranked")
    compare.add_argument("date", type=iso_date, help="purchase date, YYYY-MM-DD")
    compare.add_argument("--amount", type=positive_number, default=Decimal("1000"),
                         help="amount to invest in each (default 1000)")
    compare.add_argument("--currency", default="EUR", help="currency of --amount (default EUR)")
    compare.add_argument("--to", type=iso_date, help="valuation date (default: latest price)")

    portfolio = commands.add_parser("portfolio", help="holdings and performance of the demo account")
    portfolio.add_argument("--account", default="Main", help="account name (default Main)")
    portfolio.add_argument("--as-of", type=iso_date, help="valuation date (default today)")
    portfolio.add_argument("--history", action="store_true", help="also show the value at each year end")

    return parser


COMMANDS = {"list": cmd_list, "whatif": cmd_whatif, "compare": cmd_compare, "portfolio": cmd_portfolio}


def main(argv: list[str] | None = None) -> None:
    """Parse the arguments and run the chosen command; errors end the program with status 1."""
    args = build_parser().parse_args(argv)
    try:
        with connect() as conn:
            COMMANDS[args.command](conn, args)
    except FolioError as exc:
        console.print(f"[bold red]Error:[/] {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()

"""
python scripts\folio.py list
python scripts\folio.py whatif AAPL 2015-01-02 --shares 10
python scripts\folio.py whatif NVDA 2016-01-04 --amount 1000
python scripts\folio.py whatif MSFT 2010-01-04 --amount 2000 --currency USD --to 2020-12-31
python scripts\folio.py compare 2016-01-04 --amount 1000
python scripts\folio.py portfolio --history
python scripts\folio.py portfolio --as-of 2022-12-31
"""