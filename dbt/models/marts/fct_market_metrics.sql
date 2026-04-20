{{
  config(
    materialized="table",
    tags=["marts", "gold", "grafana"],
  )
}}

with ohlcv as (
  select * from {{ ref("int_ohlcv_1m") }}
),

joined as (
  select
    o.exchange,
    o.symbol,
    o.metric_ts,
    o.metric_date,
    o.open_price,
    o.high_price,
    o.low_price,
    o.close_price,
    o.base_volume,
    o.trade_count,
    o.vwap,
    d.avg_spread_bps,
    d.avg_mid_price,
    d.median_mid_price
  from ohlcv o
  left join {{ ref("int_depth_1m") }} d
    on o.exchange = d.exchange
    and o.symbol = d.symbol
    and o.metric_ts = d.metric_ts
),

returns as (
  select
    *,
    safe_ln(safe_divide(close_price, lag(close_price) over (
      partition by exchange, symbol
      order by metric_ts
    ))) as log_close_return
  from joined
),

vol as (
  select
    *,
    stddev_samp(log_close_return) over (
      partition by exchange, symbol
      order by metric_ts
      rows between 14 preceding and current row
    ) as realized_vol_15m,
    stddev_samp(log_close_return) over (
      partition by exchange, symbol
      order by metric_ts
      rows between 59 preceding and current row
    ) as realized_vol_60m
  from returns
)

select
  exchange,
  symbol,
  metric_ts,
  metric_date,
  open_price as open,
  high_price as high,
  low_price as low,
  close_price as close,
  base_volume as volume,
  vwap,
  avg_spread_bps as spread_bps,
  realized_vol_15m as volatility,
  realized_vol_60m as volatility_60m,
  trade_count,
  avg_mid_price,
  median_mid_price
from vol
