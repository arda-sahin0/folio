SELECT a.sector,
       a.ticker AS ticker_a,
       b.ticker AS ticker_b,
       a.mic_code <> b.mic_code                              AS cross_exchange,
       split_part(a.name, ' ', 1) = split_part(b.name, ' ', 1) AS same_first_word
FROM securities a
         JOIN securities b
              ON b.sector = a.sector
                  AND a.security_id < b.security_id
ORDER BY a.sector, ticker_a, ticker_b;