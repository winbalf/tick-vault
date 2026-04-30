{{
  config(
    materialized="view",
    tags=["staging", "silver", "rest_quotes"],
  )
}}

with bronze as (
  select
    stream_kind,
    payload,
    exchange,
    symbol,
    ingest_ts,
    kafka_topic,
    kafka_partition,
    kafka_offset,
    kafka_ts,
    dt
  from {{ source("bronze", "tickvault_bronze") }}
  where stream_kind in ("coingecko", "cryptocompare")
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
    ) as quote_key,
    coalesce(
      timestamp_millis(safe_cast(json_value(payload, "$.event_ts_ms") as int64)),
      kafka_ts
    ) as event_ts,
    safe_cast(json_value(payload, "$.quote_id") as string) as quote_id,
    safe_cast(json_value(payload, "$.price_usd") as numeric) as price_usd
  from bronze
),

filtered as (
  select
    *
  from parsed
  where event_ts is not null
    and exchange is not null
    and symbol is not null
    and quote_id is not null
    and price_usd is not null
    and price_usd > 0
),

deduped as (
  select
    *
  from filtered
  qualify row_number() over (
    partition by quote_key
    order by ingest_ts desc, event_ts desc
  ) = 1
)

select
  quote_key,
  stream_kind,
  kafka_topic,
  kafka_partition,
  kafka_offset,
  kafka_ts,
  dt,
  exchange,
  symbol,
  quote_id,
  event_ts,
  price_usd,
  ingest_ts
from deduped
