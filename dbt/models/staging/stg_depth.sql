-- to run:
-- dbt run -m staging.stg_depth --full-refresh
-- dbt test --select staging.stg_depth
-- dbt docs generate 
-- dbt docs serve 
{{
  config(
    materialized="view",
    tags=["staging", "silver", "depth"],
  )
}}

-- this is the bronze layer, the raw data from the source
with bronze as (
  select
    stream_kind,
    payload,
    exchange,
    symbol,
    event_ts_ms,
    ingest_ts,
    kafka_topic,
    kafka_partition,
    kafka_offset,
    kafka_ts,
    dt
  from {{ source("bronze", "tickvault_bronze") }}
  where stream_kind = "depth"
),

-- this is the silver layer, the parsed data
parsed as (
  select
    *,
    -- this is the surrogate key for the depth data
    concat(
      coalesce(kafka_topic, ""),
      "|",
      cast(kafka_partition as string),
      "|",
      cast(kafka_offset as string)
    ) as depth_key,
    -- this is the event time for the depth data
    coalesce(
      timestamp_millis(safe_cast(json_value(payload, "$.event_ts_ms") as int64)),
      kafka_ts
    ) as event_ts,
    -- this is the update id for the depth data
    safe_cast(json_value(payload, "$.update_id") as string) as update_id,
    -- this is the best bid price for the depth data
    safe_cast(json_value(payload, "$.bids[0].price") as numeric) as best_bid_price,
    -- this is the best bid quantity for the depth data
    safe_cast(json_value(payload, "$.bids[0].qty") as numeric) as best_bid_qty,
    -- this is the best ask price for the depth data
    safe_cast(json_value(payload, "$.asks[0].price") as numeric) as best_ask_price,
    -- this is the best ask quantity for the depth data
    safe_cast(json_value(payload, "$.asks[0].qty") as numeric) as best_ask_qty
  from bronze
),

-- this is the gold layer, the spread data
-- this is the spread data for the depth data
-- the spread is the difference between the best bid and the best ask
-- the mid price is the average of the best bid and the best ask
spread as (
  select
    *,
    -- this is the mid price for the depth data
    safe_divide(best_bid_price + best_ask_price, 2) as mid_price,
    -- this is the spread absolute for the depth data
    best_ask_price - best_bid_price as spread_abs,
    -- this is the spread in basis points for the depth data
    -- the spread in basis points is calculated by dividing the spread by the mid price and multiplying by 10000
    10000 * safe_divide(best_ask_price - best_bid_price, safe_divide(best_bid_price + best_ask_price, 2)) as spread_bps
  from parsed
  where best_bid_price is not null
    and best_ask_price is not null
    and best_bid_qty is not null
    and best_ask_qty is not null
    and event_ts is not null
    -- this is the exchange for the depth data
    and exchange is not null
    and symbol is not null
    and best_bid_price > 0
    and best_ask_price > 0
    and best_ask_price > best_bid_price
),

-- this is the gold layer, the deduped data
deduped as (
  select
    *
  from spread
  -- this is the deduped data for the depth data
  qualify row_number() over (
    -- this is the deduplication key for the depth data
    partition by kafka_topic, kafka_partition, kafka_offset
    -- this is the order by for the depth data
    order by kafka_offset
  ) = 1
),

mapped as (
  select
    d.*,
    m.base_asset,
    m.quote_asset,
    coalesce(
      case
        when m.base_asset is not null and m.quote_asset is not null
          then concat(m.base_asset, '-', m.quote_asset)
      end,
      d.symbol
    ) as instrument_id
  from deduped d
  left join {{ ref("instrument_map") }} m
    on lower(d.exchange) = lower(m.exchange)
    and d.symbol = m.symbol
)

-- this is the gold layer, the final data
select
  depth_key,
  stream_kind,
  kafka_topic,
  kafka_partition,
  kafka_offset,
  kafka_ts,
  dt,
  exchange,
  symbol,
  base_asset,
  quote_asset,
  instrument_id,
  update_id,
  event_ts,
  best_bid_price,
  best_bid_qty,
  best_ask_price,
  best_ask_qty,
  mid_price,
  spread_abs,
  spread_bps,
  ingest_ts
from mapped
