-- BigQuery external tables over Hive-style partitions written by Flink:
--   gs://BUCKET/bronze/dt=YYYY-MM-DD/symbol=PATH_SAFE_SYMBOL/exchange=VENUE/*.parquet
--
-- Replace PROJECT, DATASET, and BUCKET before running in the bq CLI or console.

CREATE OR REPLACE EXTERNAL TABLE `PROJECT.DATASET.tickvault_bronze`
(
  stream_kind STRING,
  payload STRING,
  exchange STRING,
  symbol STRING,
  event_ts_ms INT64,
  ingest_ts STRING,
  kafka_topic STRING,
  kafka_partition INT64,
  kafka_offset INT64,
  kafka_ts TIMESTAMP,
  dt STRING
)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://BUCKET/bronze/**'],
  hive_partition_uri_prefix = 'gs://BUCKET/bronze',
  require_hive_partition_filter = FALSE
);

-- Partition pruning example (uses dt + symbol + exchange folders):
-- SELECT COUNT(*) AS rows_for_day
-- FROM `PROJECT.DATASET.tickvault_bronze`
-- WHERE dt = '2026-04-17' AND exchange = 'binance' AND symbol = 'BTCUSDT';
