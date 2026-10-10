"""
scripts/fetch_fx.py

Downloads the European Central Bank's euro foreign exchange reference rates
(one fixing per business day since 4 January 1999) and writes them in LONG
format, one row per (date, currency):

    data/fx_rates.csv     date,currency,rate

A row means: on <date>, 1 EUR = <rate> <currency>.

The ECB publishes a WIDE file, one column per currency, with "N/A" wherever a
currency has no rate (e.g. the Turkish lira before it existed, or currencies
that were later replaced by the euro). Reshaping it here keeps the SQL loader
the same shape as all the others. "N/A" cells are skipped: a missing rate is an
absence, not a bad value.

Only the standard library is used, so it runs in any Python.

Usage:
    python scripts/fetch_fx.py
    python scripts/fetch_fx.py --file path/to/eurofxref-hist.zip   # offline / testing
"""

import argparse
import csv
import io
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "fx_rates.csv"
URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.zip"


def read_source(path: str | None) -> str:
    """Return the ECB CSV text, from the web or from a local .zip/.csv."""
    if path is None:
        with urllib.request.urlopen(URL, timeout=60) as resp:
            payload = resp.read()
    else:
        payload = Path(path).read_bytes()
        if not path.lower().endswith(".zip"):
            return payload.decode("utf-8-sig")

    with zipfile.ZipFile(io.BytesIO(payload)) as z:
        csv_names = [n for n in z.namelist() if n.lower().endswith(".csv")]
        if not csv_names:
            raise ValueError(f"no CSV inside the ECB archive: {z.namelist()}")
        return z.read(csv_names[0]).decode("utf-8-sig")


def to_long(text: str) -> list[list[str]]:
    """Wide (Date, USD, JPY, ...) -> long [date, currency, rate]."""
    rows = []
    for record in csv.DictReader(io.StringIO(text)):
        day = (record.get("Date") or "").strip()
        for currency, value in record.items():
            if not currency or currency == "Date" or not isinstance(value, str):
                continue
            value = value.strip()
            if value in ("", "N/A"):
                continue
            rows.append([day, currency.strip(), value])
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--file", help="read a downloaded eurofxref-hist .zip or .csv instead")
    args = parser.parse_args()

    try:
        rows = to_long(read_source(args.file))
    except Exception as exc:
        sys.exit(f"Could not get ECB rates: {exc}\nNothing was written; {OUT.name} is unchanged.")

    usd = [r for r in rows if r[1] == "USD"]
    if len(rows) < 1000 or not usd:
        sys.exit(f"ECB data looks wrong ({len(rows)} rows, {len(usd)} USD rows). "
                 f"Nothing was written; {OUT.name} is unchanged.")

    rows.sort(key=lambda r: (r[0], r[1]))

    OUT.parent.mkdir(exist_ok=True)
    tmp = OUT.with_suffix(".csv.tmp")
    with tmp.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["date", "currency", "rate"])
        writer.writerows(rows)
    os.replace(tmp, OUT)

    currencies = sorted({r[1] for r in rows})
    print(f"data/fx_rates.csv  {len(rows):>7} rows")
    print(f"dates              {rows[0][0]} .. {rows[-1][0]}")
    print(f"currencies         {len(currencies)}: {' '.join(currencies)}")
    latest = max(usd)
    print(f"latest EUR/USD     {latest[0]}  1 EUR = {latest[2]} USD")


if __name__ == "__main__":
    main()
