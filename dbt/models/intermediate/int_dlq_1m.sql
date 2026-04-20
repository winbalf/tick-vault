{{
  config(
    materialized="table",
    tags=["intermediate", "silver", "quality", "dlq"],
  )
}}

select
  timestamp_trunc(kafka_ts, minute) as metric_ts,
  date(timestamp_trunc(kafka_ts, minute)) as metric_date,
  count(*) as dead_letter_count
from {{ source("bronze", "tickvault_bronze") }}
where kafka_topic like "dlq.%"
group by metric_ts, metric_date
