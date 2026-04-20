-- Fails if more than one row exists for the same exchange, symbol, and minute.
select exchange, symbol, metric_ts, count(*) as row_count
from {{ ref("int_ohlcv_1m") }}
group by exchange, symbol, metric_ts
having count(*) > 1
