{{
  config(
    materialized="table",
    tags=["marts", "gold", "reporting", "cross_exchange"],
  )
}}

with base as (
  select
    metric_ts,
    metric_date,
    base_asset,
    exchange,
    symbol,
    instrument_id,
    close as close_price_usd
  from {{ ref("fct_market_metrics") }}
  where base_asset is not null
    and close is not null
),

multi_exchange as (
  select
    *,
    count(distinct exchange) over (
      partition by metric_ts, base_asset
    ) as exchanges_available
  from base
  qualify exchanges_available > 1
),

scored as (
  select
    *,
    min(close_price_usd) over (
      partition by metric_ts, base_asset
    ) as cheapest_price_usd,
    max(close_price_usd) over (
      partition by metric_ts, base_asset
    ) as most_expensive_price_usd,
    first_value(exchange) over (
      partition by metric_ts, base_asset
      order by close_price_usd asc, exchange asc
    ) as cheapest_exchange,
    first_value(exchange) over (
      partition by metric_ts, base_asset
      order by close_price_usd desc, exchange asc
    ) as most_expensive_exchange,
    first_value(symbol) over (
      partition by metric_ts, base_asset
      order by close_price_usd asc, exchange asc
    ) as cheapest_symbol,
    first_value(symbol) over (
      partition by metric_ts, base_asset
      order by close_price_usd desc, exchange asc
    ) as most_expensive_symbol,
    row_number() over (
      partition by metric_ts, base_asset
      order by close_price_usd asc, exchange asc
    ) as price_rank_asc
  from multi_exchange
)

select
  metric_ts,
  metric_date,
  base_asset,
  exchange,
  symbol,
  instrument_id,
  exchanges_available,
  close_price_usd,
  cheapest_exchange,
  cheapest_symbol,
  cheapest_price_usd,
  most_expensive_exchange,
  most_expensive_symbol,
  most_expensive_price_usd,
  price_rank_asc,
  price_rank_asc = 1 as is_cheapest_at_ts,
  close_price_usd = most_expensive_price_usd as is_most_expensive_at_ts,
  close_price_usd - cheapest_price_usd as premium_vs_cheapest_usd,
  safe_divide(
    close_price_usd - cheapest_price_usd,
    cheapest_price_usd
  ) * 100 as premium_vs_cheapest_pct,
  most_expensive_price_usd - cheapest_price_usd as cross_exchange_spread_usd,
  safe_divide(
    most_expensive_price_usd - cheapest_price_usd,
    cheapest_price_usd
  ) * 100 as cross_exchange_spread_pct
from scored
