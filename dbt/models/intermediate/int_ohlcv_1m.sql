{{
  config(
    materialized="table",
    tags=["intermediate", "silver", "ohlcv"],
  )
}}

select
  exchange,
  symbol,
  timestamp_trunc(event_ts, minute) as metric_ts,
  date(timestamp_trunc(event_ts, minute)) as metric_date,
  min_by(price, event_ts) as open_price,
  max(price) as high_price,
  min(price) as low_price,
  max_by(price, event_ts) as close_price,
  sum(quantity) as base_volume,
  count(*) as trade_count,
  safe_divide(
    sum(price * quantity),
    nullif(sum(quantity), 0)
  ) as vwap
from {{ ref("stg_trades") }}
group by exchange, symbol, metric_ts, metric_date
