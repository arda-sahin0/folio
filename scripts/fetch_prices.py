import csv
import subprocess
import sys
import time
from pathlib import Path
 
import pandas as pd
import yfinance as yf
 
ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
PERIOD = "5y"
 
 
def load_env() -> dict:
    """Read .env into a plain dict. Same format the PowerShell scripts use."""
    env = {}
    for line in (ROOT / ".env").read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip()
    return env
 
 
def fetch_symbol_list(env: dict) -> list[str]:
    """The download list comes from the database, not from a hardcoded array."""
    result = subprocess.run(
        [
            "docker", "compose", "exec", "-T", "db", "psql",
            "-U", env["POSTGRES_USER"], "-d", env["POSTGRES_DB"],
            "-t", "-A", "-c",
            "SELECT symbol FROM security_sources WHERE source = 'yfinance' ORDER BY symbol",
        ],
        cwd=ROOT, capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(f"Could not read security_sources:\n{result.stderr}")
    return [s.strip() for s in result.stdout.splitlines() if s.strip()]
 
 
def write_csv(path: Path, header: list[str], rows: list[list]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
 
 
def main() -> None:
    env = load_env()
    symbols = fetch_symbol_list(env)
 
    if not symbols:
        sys.exit("No yfinance symbols registered. Run scripts\\load.ps1 first.")
 
    print(f"{len(symbols)} symbol(s) to fetch, period={PERIOD}\n")
    DATA.mkdir(exist_ok=True)
 
    price_rows: list[list] = []
    split_rows: list[list] = []
    dividend_rows: list[list] = []
    failed: list[str] = []
 
    for symbol in symbols:
        try:
            # auto_adjust=False is essential: we want RAW prices
            # Adjustment is computed from corporate_actions in M5, and adjusting
            # already-adjusted data would double-count every split.
            # actions=True (the default) adds Dividends and "Stock Splits" columns,
            # so one request gives us all three datasets.
            bars = yf.Ticker(symbol).history(period=PERIOD, auto_adjust=False)
        except Exception as exc:                      # noqa: BLE001
            failed.append(f"{symbol}: {exc}")
            continue
 
        if bars.empty:
            failed.append(f"{symbol}: no data returned (wrong symbol?)")
            continue
 
        n_splits = n_dividends = 0
 
        for timestamp, row in bars.iterrows():
            day = timestamp.date().isoformat()
 
            price_rows.append([
                symbol, day,
                row["Open"], row["High"], row["Low"], row["Close"],
                "" if pd.isna(row["Volume"]) else int(row["Volume"]),
            ])
 
            split_ratio = row.get("Stock Splits", 0)
            if not pd.isna(split_ratio) and split_ratio != 0:
                split_rows.append([symbol, day, split_ratio])
                n_splits += 1
 
            dividend = row.get("Dividends", 0)
            if not pd.isna(dividend) and dividend != 0:
                dividend_rows.append([symbol, day, dividend])
                n_dividends += 1
 
        print(f"  {symbol:<12} {len(bars):>6} bars  "
              f"{n_splits:>2} splits  {n_dividends:>3} dividends")
 
        time.sleep(0.5)   # be polite
 
    write_csv(DATA / "prices.csv",
              ["symbol", "date", "open", "high", "low", "close", "volume"], price_rows)
    write_csv(DATA / "splits.csv",
              ["symbol", "ex_date", "ratio"], split_rows)
    write_csv(DATA / "dividends.csv",
              ["symbol", "ex_date", "amount"], dividend_rows)
 
    print(f"\ndata/prices.csv     {len(price_rows):>7} rows")
    print(f"data/splits.csv     {len(split_rows):>7} rows")
    print(f"data/dividends.csv  {len(dividend_rows):>7} rows")
 
    if failed:
        print(f"\nFailed: {len(failed)}", file=sys.stderr)
        for line in failed:
            print(f"  {line}", file=sys.stderr)
        sys.exit(1)
 
 
if __name__ == "__main__":
    main()