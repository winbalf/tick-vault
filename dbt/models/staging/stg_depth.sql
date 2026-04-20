{{
  config(
    materialized="view",
    tags=["staging", "silver", "depth"],
  )
}}

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

parsed as (
  select
    *,
    concat(
      coalesce(kafka_topic, ""),
      "|",
      cast(kafka_partition as string),
      "|",
      cast(kafka_offset as string)
    ) as depth_key,
    coalesce(
      timestamp_millis(safe_cast(json_value(payload, "$.event_ts_ms") as int64)),
      kafka_ts
    ) as event_ts,
    safe_cast(json_value(payload, "$.update_id") as string) as update_id,
    safe_cast(json_value(payload, "$.bids[0].price") as numeric) as best_bid_price,
    safe_cast(json_value(payload, "$.bids[0].qty") as numeric) as best_bid_qty,
    safe_cast(json_value(payload, "$.asks[0].price") as numeric) as best_ask_price,
    safe_cast(json_value(payload, "$.asks[0].qty") as numeric) as best_ask_qty
  from bronze
),

spread as (
  select
    *,
    safe_divide(best_bid_price + best_ask_price, 2) as mid_price,
    best_ask_price - best_bid_price as spread_abs,
    10000 * safe_divide(best_ask_price - best_bid_price, safe_divide(best_bid_price + best_ask_price, 2)) as spread_bps
  from parsed
  where best_bid_price is not null
    and best_ask_price is not null
    and best_bid_qty is not null
    and best_ask_qty is not null
    and event_ts is not null
    and exchange is not null
    and symbol is not null
    and best_bid_price > 0
    and best_ask_price > 0
    and best_ask_price > best_bid_price
),

deduped as (
  select
    *
  from spread
  qualify row_number() over (
    partition by kafka_topic, kafka_partition, kafka_offset
    order by kafka_offset
  ) = 1
)

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
from deduped
