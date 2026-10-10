CREATE OR REPLACE FUNCTION eur_rate(p_currency text, p_on date)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT CASE
               WHEN p_currency = 'EUR' THEN 1::numeric
               ELSE (SELECT f.rate
                     FROM fx_rates f
                     WHERE f.base_currency  = 'EUR'
                       AND f.quote_currency = p_currency
                       AND f.rate_date     <= p_on
                       AND f.rate_date      > p_on - 7
                     ORDER BY f.rate_date DESC
                     LIMIT 1)
           END
$$;

COMMENT ON FUNCTION eur_rate(text, date) IS
    'Units of p_currency per 1 EUR on p_on: the latest ECB rate on or before that day (as-of lookup), NULL if none within 7 days.';


CREATE OR REPLACE FUNCTION whatif(
    p_ticker          text,
    p_start           date,
    p_shares          numeric DEFAULT NULL,
    p_amount          numeric DEFAULT NULL,
    p_amount_currency text    DEFAULT 'EUR',
    p_end             date    DEFAULT NULL
)
RETURNS TABLE (
    ticker             text,
    name               text,
    currency           text,
    buy_date           date,
    buy_price          numeric,
    shares_bought      numeric,
    cost               numeric,
    cost_eur           numeric,
    end_date           date,
    end_price          numeric,
    split_factor       numeric,
    shares_now         numeric,
    value              numeric,
    value_eur          numeric,
    dividends          numeric,
    dividends_eur      numeric,
    profit             numeric,
    profit_eur         numeric,
    return_pct         numeric,
    return_eur_pct     numeric,
    annualized_eur_pct numeric,
    years              numeric,
    volatility_pct     numeric,
    max_drawdown_pct   numeric,
    drawdown_peak      date,
    drawdown_trough    date,
    best_day           date,
    best_day_pct       numeric,
    worst_day          date,
    worst_day_pct      numeric
)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_id       integer;
    v_ticker   text;
    v_name     text;
    v_currency text;
    v_matches  integer;
    v_buy      date;
    v_end      date;
    v_price    numeric;
    v_shares   numeric;
    v_amount   numeric;
    v_from     numeric;
    v_to       numeric;
BEGIN
    IF (p_shares IS NULL) = (p_amount IS NULL) THEN
        RAISE EXCEPTION 'give exactly one of: a number of shares, or an amount of money';
    END IF;
    IF coalesce(p_shares, p_amount) <= 0 THEN
        RAISE EXCEPTION 'shares and amounts must be positive';
    END IF;

    SELECT count(*), min(s.security_id), min(s.ticker), min(s.name), min(s.currency)
    INTO v_matches, v_id, v_ticker, v_name, v_currency
    FROM securities s
    WHERE upper(s.ticker) = upper(p_ticker);

    IF v_matches = 0 THEN
        RAISE EXCEPTION 'unknown ticker %', p_ticker;
    ELSIF v_matches > 1 THEN
        RAISE EXCEPTION 'ticker % is listed on more than one exchange', p_ticker;
    END IF;

    SELECT min(p.trade_date) INTO v_buy
    FROM daily_prices p
    WHERE p.security_id = v_id AND p.trade_date >= p_start;

    SELECT max(p.trade_date) INTO v_end
    FROM daily_prices p
    WHERE p.security_id = v_id AND p.trade_date <= coalesce(p_end, 'infinity'::date);

    IF v_buy IS NULL THEN
        RAISE EXCEPTION 'no % prices on or after %', v_ticker, p_start;
    ELSIF v_end IS NULL OR v_end <= v_buy THEN
        RAISE EXCEPTION 'no % prices after the buy date %', v_ticker, v_buy;
    END IF;

    SELECT p.close INTO v_price
    FROM daily_prices p
    WHERE p.security_id = v_id AND p.trade_date = v_buy;

    IF p_shares IS NOT NULL THEN
        v_shares := p_shares;
    ELSE
        IF upper(p_amount_currency) = v_currency THEN
            v_amount := p_amount;
        ELSE
            v_from := eur_rate(upper(p_amount_currency), v_buy);
            v_to   := eur_rate(v_currency, v_buy);
            IF v_from IS NULL OR v_to IS NULL THEN
                RAISE EXCEPTION 'no ECB rate to convert % to % on %', upper(p_amount_currency), v_currency, v_buy;
            END IF;
            v_amount := p_amount / v_from * v_to;
        END IF;
        v_shares := round(v_amount / v_price, 6);
    END IF;

    RETURN QUERY
    WITH splits AS (
        SELECT ca.ex_date, ca.ratio
        FROM corporate_actions ca
        WHERE ca.security_id = v_id
          AND ca.action_type = 'split'
          AND ca.ex_date > v_buy
          AND ca.ex_date <= v_end
    ), factor AS (
        SELECT coalesce(exp(sum(ln(sp.ratio))), 1) AS f FROM splits sp
    ), divs AS (
        SELECT ca.ex_date,
               ca.amount * v_shares * coalesce(h.f, 1) AS paid
        FROM corporate_actions ca
        CROSS JOIN LATERAL (
            SELECT exp(sum(ln(sp.ratio))) AS f
            FROM splits sp
            WHERE sp.ex_date <= ca.ex_date
        ) h
        WHERE ca.security_id = v_id
          AND ca.action_type = 'dividend'
          AND ca.ex_date > v_buy
          AND ca.ex_date <= v_end
    ), div_totals AS (
        SELECT coalesce(sum(d.paid), 0)                                AS paid,
               coalesce(sum(d.paid / eur_rate(v_currency, d.ex_date)), 0) AS paid_eur,
               count(*) FILTER (WHERE eur_rate(v_currency, d.ex_date) IS NULL) AS missing_fx
        FROM divs d
    ), returns AS (
        SELECT p.trade_date,
               p.close * coalesce(ca.ratio, 1) / lag(p.close) OVER (ORDER BY p.trade_date) - 1 AS ret
        FROM daily_prices p
        LEFT JOIN corporate_actions ca
               ON ca.security_id = p.security_id
              AND ca.ex_date     = p.trade_date
              AND ca.action_type = 'split'
        WHERE p.security_id = v_id
          AND p.trade_date BETWEEN v_buy AND v_end
    ), growth AS (
        SELECT r.trade_date,
               r.ret,
               exp(sum(ln(1 + coalesce(r.ret, 0)::float8))
                   OVER (ORDER BY r.trade_date ROWS UNBOUNDED PRECEDING)) AS g
        FROM returns r
    ), peaks AS (
        SELECT gr.trade_date, gr.g,
               max(gr.g) OVER (ORDER BY gr.trade_date ROWS UNBOUNDED PRECEDING) AS peak
        FROM growth gr
    ), drawdowns AS (
        SELECT pk.trade_date,
               pk.g / pk.peak - 1 AS dd,
               max(CASE WHEN pk.g = pk.peak THEN pk.trade_date END)
                   OVER (ORDER BY pk.trade_date ROWS UNBOUNDED PRECEDING) AS peak_date
        FROM peaks pk
    ), worst_dd AS (
        SELECT dw.dd, dw.peak_date, dw.trade_date AS trough_date
        FROM drawdowns dw
        ORDER BY dw.dd, dw.trade_date
        LIMIT 1
    ), stats AS (
        SELECT stddev_samp(r.ret) * sqrt(252::numeric) AS vol
        FROM returns r
    ), best AS (
        SELECT r.trade_date, r.ret FROM returns r WHERE r.ret IS NOT NULL ORDER BY r.ret DESC, r.trade_date LIMIT 1
    ), worst AS (
        SELECT r.trade_date, r.ret FROM returns r WHERE r.ret IS NOT NULL ORDER BY r.ret, r.trade_date LIMIT 1
    ), result AS (
        SELECT v_shares * v_price                                       AS cost,
               v_shares * v_price / eur_rate(v_currency, v_buy)         AS cost_eur,
               p.close::numeric                                         AS end_price,
               fa.f                                                     AS split_factor,
               v_shares * fa.f                                          AS shares_now,
               v_shares * fa.f * p.close                                AS value,
               v_shares * fa.f * p.close / eur_rate(v_currency, v_end)  AS value_eur,
               dt.paid                                                  AS dividends,
               CASE WHEN dt.missing_fx = 0 THEN dt.paid_eur END         AS dividends_eur,
               (v_end - v_buy) / 365.25                                 AS years
        FROM daily_prices p
        CROSS JOIN factor fa
        CROSS JOIN div_totals dt
        WHERE p.security_id = v_id AND p.trade_date = v_end
    )
    SELECT v_ticker,
           v_name,
           v_currency,
           v_buy,
           v_price,
           v_shares,
           round(rs.cost, 2),
           round(rs.cost_eur, 2),
           v_end,
           rs.end_price,
           round(rs.split_factor, 6),
           round(rs.shares_now, 6),
           round(rs.value, 2),
           round(rs.value_eur, 2),
           round(rs.dividends, 2),
           round(rs.dividends_eur, 2),
           round(rs.value + rs.dividends - rs.cost, 2),
           round(rs.value_eur + rs.dividends_eur - rs.cost_eur, 2),
           round(100 * (rs.value + rs.dividends - rs.cost) / rs.cost, 2),
           round(100 * (rs.value_eur + rs.dividends_eur - rs.cost_eur) / rs.cost_eur, 2),
           CASE WHEN rs.years >= 1
                THEN round(100 * (power((rs.value_eur + rs.dividends_eur) / rs.cost_eur, 1 / rs.years) - 1), 2)
           END,
           round(rs.years, 2),
           round(100 * st.vol, 2),
           round(100 * wd.dd::numeric, 2),
           wd.peak_date,
           wd.trough_date,
           b.trade_date,
           round(100 * b.ret, 2),
           w.trade_date,
           round(100 * w.ret, 2)
    FROM result rs
    CROSS JOIN stats st
    CROSS JOIN worst_dd wd
    CROSS JOIN best b
    CROSS JOIN worst w;
END
$$;

COMMENT ON FUNCTION whatif(text, date, numeric, numeric, text, date) IS
    'Simulates buying a security at the close of the first session on or after p_start, either p_shares shares or p_amount money (in p_amount_currency, EUR by default), and holding it until p_end (default: latest price). Splits multiply the shares, dividends are paid out as cash, not reinvested. The annualised return is only given for holdings of a year or more.';


CREATE OR REPLACE FUNCTION portfolio_positions(p_account text DEFAULT 'Main', p_as_of date DEFAULT current_date)
RETURNS TABLE (
    ticker        text,
    currency      text,
    shares        numeric,
    price         numeric,
    price_date    date,
    value         numeric,
    value_eur     numeric,
    weight_pct    numeric,
    bought_eur    numeric,
    sold_eur      numeric,
    dividends_eur numeric,
    profit_eur    numeric
)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    IF NOT EXISTS (SELECT 1 FROM accounts a WHERE a.name = p_account) THEN
        RAISE EXCEPTION 'unknown account %', p_account;
    END IF;

    RETURN QUERY
    WITH txn AS (
        SELECT t.security_id,
               t.txn_type,
               tt.cash_sign,
               tt.affects_position,
               t.quantity * coalesce(sf.f, 1)                                AS quantity_now,
               coalesce(t.amount, t.quantity * t.price) / eur_rate(s.currency, t.trade_date) AS gross_eur
        FROM transactions t
        JOIN accounts a   ON a.account_id = t.account_id
        JOIN txn_types tt ON tt.code = t.txn_type
        JOIN securities s ON s.security_id = t.security_id
        CROSS JOIN LATERAL (
            SELECT exp(sum(ln(ca.ratio))) AS f
            FROM corporate_actions ca
            WHERE ca.security_id = t.security_id
              AND ca.action_type = 'split'
              AND ca.ex_date > t.trade_date
              AND ca.ex_date <= p_as_of
        ) sf
        WHERE a.name = p_account
          AND t.trade_date <= p_as_of
    ), per_security AS (
        SELECT x.security_id,
               sum(-x.cash_sign * x.quantity_now) FILTER (WHERE x.affects_position) AS shares,
               CASE WHEN bool_or(x.gross_eur IS NULL) FILTER (WHERE x.txn_type = 'buy') THEN NULL
                    ELSE coalesce(sum(x.gross_eur) FILTER (WHERE x.txn_type = 'buy'), 0) END      AS bought_eur,
               CASE WHEN bool_or(x.gross_eur IS NULL) FILTER (WHERE x.txn_type = 'sell') THEN NULL
                    ELSE coalesce(sum(x.gross_eur) FILTER (WHERE x.txn_type = 'sell'), 0) END     AS sold_eur,
               CASE WHEN bool_or(x.gross_eur IS NULL) FILTER (WHERE x.txn_type = 'dividend') THEN NULL
                    ELSE coalesce(sum(x.gross_eur) FILTER (WHERE x.txn_type = 'dividend'), 0) END AS dividends_eur
        FROM txn x
        GROUP BY x.security_id
    ), valued AS (
        SELECT s.ticker,
               s.currency,
               ps.shares,
               lp.close::numeric                                 AS price,
               lp.trade_date                                     AS price_date,
               CASE WHEN ps.shares = 0 THEN 0 ELSE ps.shares * lp.close END AS value,
               CASE WHEN ps.shares = 0 THEN 0
                    ELSE ps.shares * lp.close / eur_rate(s.currency, p_as_of) END AS value_eur,
               ps.bought_eur,
               ps.sold_eur,
               ps.dividends_eur
        FROM per_security ps
        JOIN securities s ON s.security_id = ps.security_id
        LEFT JOIN LATERAL (
            SELECT p.trade_date, p.close
            FROM daily_prices p
            WHERE p.security_id = ps.security_id
              AND p.trade_date <= p_as_of
            ORDER BY p.trade_date DESC
            LIMIT 1
        ) lp ON true
    )
    SELECT v.ticker,
           v.currency,
           round(v.shares, 6),
           v.price,
           v.price_date,
           round(v.value, 2),
           round(v.value_eur, 2),
           round(100 * v.value_eur / sum(v.value_eur) OVER (), 2),
           round(v.bought_eur, 2),
           round(v.sold_eur, 2),
           round(v.dividends_eur, 2),
           round(v.value_eur + v.sold_eur + v.dividends_eur - v.bought_eur, 2)
    FROM valued v
    ORDER BY v.value_eur DESC NULLS LAST, v.ticker;
END
$$;

COMMENT ON FUNCTION portfolio_positions(text, date) IS
    'Every security the account has traded, valued on p_as_of: shares held (split-adjusted), latest price, value in EUR, and profit = value + sales + dividends - purchases, with each cash flow converted at the ECB rate of its day.';


CREATE OR REPLACE FUNCTION portfolio_summary(p_account text DEFAULT 'Main', p_as_of date DEFAULT current_date)
RETURNS TABLE (
    as_of            date,
    deposits_eur     numeric,
    withdrawals_eur  numeric,
    fees_eur         numeric,
    net_invested_eur numeric,
    cash_eur         numeric,
    holdings_eur     numeric,
    total_value_eur  numeric,
    dividends_eur    numeric,
    profit_eur       numeric,
    return_pct       numeric
)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    IF NOT EXISTS (SELECT 1 FROM accounts a WHERE a.name = p_account) THEN
        RAISE EXCEPTION 'unknown account %', p_account;
    END IF;

    RETURN QUERY
    WITH flows AS (
        SELECT t.txn_type,
               tt.cash_sign * coalesce(t.amount, t.quantity * t.price)
                   / eur_rate(coalesce(s.currency, a.base_currency), t.trade_date) AS cash_eur
        FROM transactions t
        JOIN accounts a   ON a.account_id = t.account_id
        JOIN txn_types tt ON tt.code = t.txn_type
        LEFT JOIN securities s ON s.security_id = t.security_id
        WHERE a.name = p_account
          AND t.trade_date <= p_as_of
    ), totals AS (
        SELECT coalesce(sum(f.cash_eur) FILTER (WHERE f.txn_type = 'deposit'), 0)     AS deposits,
               coalesce(-sum(f.cash_eur) FILTER (WHERE f.txn_type = 'withdrawal'), 0) AS withdrawals,
               coalesce(-sum(f.cash_eur) FILTER (WHERE f.txn_type = 'fee'), 0)        AS fees,
               CASE WHEN bool_or(f.cash_eur IS NULL) FILTER (WHERE f.txn_type = 'dividend') THEN NULL
                    ELSE coalesce(sum(f.cash_eur) FILTER (WHERE f.txn_type = 'dividend'), 0) END AS dividends,
               CASE WHEN bool_or(f.cash_eur IS NULL) THEN NULL
                    ELSE coalesce(sum(f.cash_eur), 0) END                                    AS cash
        FROM flows f
    ), holdings AS (
        SELECT CASE WHEN bool_or(pp.value_eur IS NULL) THEN NULL
                    ELSE round(coalesce(sum(pp.value_eur), 0), 2) END AS value
        FROM portfolio_positions(p_account, p_as_of) pp
    )
    SELECT p_as_of,
           round(tl.deposits, 2),
           round(tl.withdrawals, 2),
           round(tl.fees, 2),
           round(tl.deposits - tl.withdrawals, 2),
           round(tl.cash, 2),
           h.value,
           round(tl.cash, 2) + h.value,
           round(tl.dividends, 2),
           round(tl.cash, 2) + h.value - round(tl.deposits - tl.withdrawals, 2),
           round(100 * (round(tl.cash, 2) + h.value - round(tl.deposits - tl.withdrawals, 2))
                 / nullif(round(tl.deposits - tl.withdrawals, 2), 0), 2)
    FROM totals tl
    CROSS JOIN holdings h;
END
$$;

COMMENT ON FUNCTION portfolio_summary(text, date) IS
    'Account totals on p_as_of in EUR: money paid in and out, cash left, holdings value, and profit = total value - net amount paid in. NULL where a price or ECB rate is missing.';
