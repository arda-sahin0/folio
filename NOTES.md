# Design notes

The decisions behind Folio, and why each one was made. Numbers refer to the full dataset (17 securities, prices back to 1962).

## Migrations and loaders are separate

`migrations/` change the **shape** of the database. They are numbered, applied once, in order, and never edited afterwards; a change is a new migration. `reset.ps1` rebuilds the whole schema from them, so the database can always be thrown away and recreated.

`loaders/` change the **contents**. They can run any number of times, and running one twice leaves the database exactly as it was (CI proves this by fingerprinting every table between two loads).

## Staging → validate → promote → reject log

Vendor files are never loaded straight into the real tables. Each loader:

1. `COPY`s the file into a staging table where every column is `text` and nothing is constrained, so a malformed row cannot abort the load;
2. sets a `reject_reason` with a `CASE` whose branch order matters: the format checks come first, so the later branches can safely cast;
3. promotes the valid rows with `INSERT … ON CONFLICT`, casting inside a `MATERIALIZED` CTE so the planner cannot move a cast in front of the filter;
4. writes every rejected row to `staging.rejects` with its reason and the raw row as `jsonb`.

Nothing disappears silently. Staged rows always equal loaded plus rejected: 159,580 + 12,282 = 171,862 price rows.

Dates are checked twice: a regex enforces the ISO format and `pg_input_is_valid(text, 'date')` checks the date exists. The regex alone accepts `2020-13-01`, which would crash the cast.

## Idempotent upserts

Re-loading uses `ON CONFLICT … DO UPDATE … WHERE (old row) IS DISTINCT FROM (new row)`. The `WHERE` skips rows that did not change, so a second load rewrites nothing. `IS DISTINCT FROM` instead of `<>` because `NULL <> NULL` is not true, which would make rows with a NULL volume look changed forever.

## Prices are stored as actually traded

Yahoo returns prices adjusted for splits even with `auto_adjust=False`. Apple's close on 2020-08-28 arrives as 124.81; it traded at 499.23, and the 4:1 split three days later was applied backwards. Adjusted prices also change every time a new split happens, so a stored history would silently go stale.

So the price loader **de-adjusts**: each bar is multiplied by the product of all split ratios with an ex-date *after* the bar (`exp(sum(ln(ratio)))`, because SQL has no product aggregate) and volume is divided by the same factor. Dividends get the same treatment. Adjusted series are derived when a query needs them, as in `queries/m4/`.

## Not all vendor history is trusted

Yahoo's Xetra data before 2004 contains hundreds of bars whose close lies outside that day's high–low range (about 300 for BMW and SAP alone). Rather than repair invented numbers, `securities.trusted_from` records the first date we accept per security, and earlier bars are rejected as `before trusted_from`. This is a judgement about the data source, so it is a separate column from `listed_on`, which is a fact about the company.

Two other vendor quirks:

- **Placeholder bars.** On some exchange holidays Yahoo emits a flat bar (open = high = low = close, volume 0). These are rejected (707 rows).
- **Zero volume on days that moved.** A bar with a real price range but volume 0 is kept, and the volume is stored as `NULL` (unknown) rather than 0, so averages skip it instead of counting a day of no trading.

## The trading calendar is derived

`trading_calendar` holds one row per exchange per session, rebuilt from the loaded prices on every load (`TRUNCATE` + `INSERT`, never upserted, because days can also disappear). It tells "the exchange was closed" apart from "a bar is missing". Its blind spot is deliberate and documented: a day on which *every* security of an exchange is missing cannot be detected.

## FX: one pivot currency

The ECB publishes rates as 1 EUR = x units of another currency, once per TARGET2 business day. Every rate is stored with EUR as the base (enforced by a `CHECK`), and any cross rate (USD→JPY) is derived from two EUR rates instead of being stored. Rates for currencies that no longer exist (CYP, TRL, HRK, …) are rejected as `unknown currency`, because the currency list holds only active ISO codes.

The ECB and the NYSE have different holidays, so a US trading day can have no rate (Easter Monday, 1 May, 26 December). Today those days get no rate and are skipped; M5 replaces that with an as-of join that uses the latest available rate.

## The ledger is append-only

A booked transaction never changes. Each one has an `external_ref` (`UNIQUE`), loads use `ON CONFLICT (external_ref) DO NOTHING`, and a CSV row that differs from what is already booked is rejected as `differs from booked transaction` instead of overwriting history. Real ledgers correct mistakes with a new, reversing entry.

Transaction shape is enforced by one `CHECK`: a buy or sell needs a security, quantity and price and no amount; a deposit, withdrawal or fee needs an amount and no security; a dividend needs a security and an amount. A malformed row in the hand-written ledger fails the whole load on purpose, so a typo is noticed instead of disappearing into the reject log.

## Store the minimum, derive the rest

Positions, cash balances, trade amounts, adjusted prices, returns and cross rates are not stored. They are computed from the ledger, the raw prices and the EUR rates, so there is exactly one source for each fact and nothing to keep in sync.

## Lookup tables carry behaviour

`txn_types` is not just a list of names: `cash_sign` (−1, 0, 1) says how each type moves cash, and `affects_position` whether it changes holdings. Queries can use these columns instead of hard-coding `CASE txn_type WHEN …` (the position check in `tests/test_portfolio.sql` does). Sectors are a lookup table too, so a typo like `Technology` is rejected by a foreign key.

## Valuing the account in EUR

The account is kept in EUR, but it buys US stocks and receives dollar dividends. `transactions` has no currency column because the currency follows from the row: trades and dividends are in the security's currency, deposits, withdrawals and fees in the account's base currency. Every flow is converted at the ECB rate of its own day (`eur_rate`, an as-of lookup: the latest rate on or before the date, ignored if older than a week), as if the broker converted automatically. Holdings are converted at the rate of the valuation date, so the reported profit includes the currency effect.

If any flow or holding cannot be converted, the totals come back as NULL instead of silently leaving it out: an unknown number is better than a wrong one.

## Known limitations

- The ledger has no explicit currency conversions: dollars for US purchases are assumed to be bought at the ECB rate of the trade date. Real brokers charge a spread.
- Portfolio return is profit divided by the net amount paid in. Time- and money-weighted returns, which account for when money was added, are M5.
- If Yahoo's split list misses a split, that stock's older prices stay adjusted for it. SAP looks like such a case: its December 2007 4:1 split is not listed and there is no jump in the series, so its 2004 prices are about a quarter of what traded. Returns are still right because the series is continuous, but the stored price is not what traded.
- Dividends are booked on the ex-date, not the payment date.
- Returns in `queries/m4/` are price returns; dividends are not reinvested.
- Fetching during market hours stores an unfinished bar for that day. The next load overwrites it, but queries in between see a partial day.
- No FX rates before 1999 (the ECB series starts with the euro).
