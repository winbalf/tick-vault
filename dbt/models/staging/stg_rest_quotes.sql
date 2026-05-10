-- to run:
-- dbt run -m staging.stg_rest_quotes --full-refresh
-- dbt test --select staging.stg_rest_quotes
-- dbt docs generate 
-- dbt docs serve 
{{
  config(
    materialized="view",
    tags=["staging", "silver", "rest_quotes"],
  )
}}

-- this is the bronze layer, the raw data from the source
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

-- this is the silver layer, the parsed data
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

-- this is the gold layer, the filtered data
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

-- this is the gold layer, the deduped data
deduped as (
  select
    *
  from filtered
  qualify row_number() over (
    partition by quote_key
    order by ingest_ts desc, event_ts desc
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
  quote_key,
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
  quote_id,
  event_ts,
  price_usd,
  ingest_ts
from mapped
