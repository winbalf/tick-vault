-- to run:
-- dbt run -m staging.stg_trades --full-refresh
-- dbt test --select staging.stg_trades
-- dbt docs generate 
-- dbt docs serve 
{{
  config(
    materialized="view",
    tags=["staging", "silver", "trades"],
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
  where stream_kind = "trades"
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
    ) as trade_key,
    coalesce(
      timestamp_millis(safe_cast(json_value(payload, "$.event_ts_ms") as int64)),
      kafka_ts
    ) as event_ts,
    safe_cast(json_value(payload, "$.trade_id") as string) as trade_id,
    safe_cast(json_value(payload, "$.price") as numeric) as price,
    safe_cast(json_value(payload, "$.quantity") as numeric) as quantity,
    case
      when lower(json_value(payload, "$.is_buyer_maker")) in ("true", "1", "t") then true
      when lower(json_value(payload, "$.is_buyer_maker")) in ("false", "0", "f") then false
      else cast(null as bool) 
    end as is_buyer_maker
  from bronze
),

-- this is the gold layer, the filtered data
filtered as (
  select
    *
  from parsed
  where trade_id is not null
    and price is not null
    and quantity is not null
    and event_ts is not null
    and exchange is not null
    and symbol is not null
    and price > 0
    and quantity > 0
),

-- Bronze can contain duplicate rows for the same Kafka record (e.g. overlapping
-- external table paths / at-least-once duplicates). Collapse those first so
-- trade_key stays unique, then keep one row per logical trade for OHLCV.
dedup_kafka as (
  select
    *
  from filtered
  qualify row_number() over (
    partition by trade_key
    order by ingest_ts desc, event_ts desc
  ) = 1
),

deduped as (
  select
    *
  from dedup_kafka
  qualify row_number() over (
    partition by exchange, symbol, trade_id
    order by kafka_offset desc, kafka_partition desc, kafka_topic desc
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

select
  trade_key,
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
  trade_id,
  event_ts,
  price,
  quantity,
  is_buyer_maker,
  ingest_ts
from mapped
