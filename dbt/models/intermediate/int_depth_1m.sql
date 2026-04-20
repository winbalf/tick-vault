{{
  config(
    materialized="table",
    tags=["intermediate", "silver", "depth"],
  )
}}

select
  exchange,
  symbol,
  timestamp_trunc(event_ts, minute) as metric_ts,
  date(timestamp_trunc(event_ts, minute)) as metric_date,
  avg(spread_bps) as avg_spread_bps,
  avg(mid_price) as avg_mid_price,
  approx_quantiles(mid_price, 100)[offset(50)] as median_mid_price
from {{ ref("stg_depth") }}
group by exchange, symbol, metric_ts, metric_date
