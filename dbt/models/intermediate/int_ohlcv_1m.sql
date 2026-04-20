{{
  config(
    materialized="table",
    tags=["intermediate", "silver", "ohlcv"],
  )
}}

with candles as (
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
),
with_rollups as (
  select
    *,
    avg(close_price) over (
      partition by exchange, symbol
      order by metric_ts
      rows between 4 preceding and current row
    ) as rolling_avg_close_5m
  from candles
)
select
  exchange,
  symbol,
  metric_ts,
  metric_date,
  open_price,
  high_price,
  low_price,
  close_price,
  base_volume,
  trade_count,
  vwap,
  rolling_avg_close_5m,
  base_volume = 0 as zero_volume_flag,
  coalesce(abs(safe_divide(close_price - rolling_avg_close_5m, rolling_avg_close_5m)) > 0.10, false) as price_spike_flag,
  (base_volume = 0) or coalesce(abs(safe_divide(close_price - rolling_avg_close_5m, rolling_avg_close_5m)) > 0.10, false) as anomaly_flag
from with_rollups
