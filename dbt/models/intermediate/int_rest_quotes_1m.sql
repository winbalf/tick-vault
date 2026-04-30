{{
  config(
    materialized="table",
    tags=["intermediate", "silver", "rest_quotes"],
  )
}}

select
  exchange,
  symbol,
  timestamp_trunc(event_ts, minute) as metric_ts,
  date(timestamp_trunc(event_ts, minute)) as metric_date,
  min_by(price_usd, event_ts) as open_price,
  max(price_usd) as high_price,
  min(price_usd) as low_price,
  max_by(price_usd, event_ts) as close_price,
  cast(0 as numeric) as base_volume,
  count(*) as quote_count,
  avg(price_usd) as vwap
from {{ ref("stg_rest_quotes") }}
group by exchange, symbol, metric_ts, metric_date
