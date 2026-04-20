#!/usr/bin/env bash
# Create or replace the bronze external table over gs://BUCKET/bronze/* (Hive partitions).
#
# Requires: bq CLI, GCP_PROJECT_ID, GCS_BUCKET (no gs:// prefix)
# Optional: BQ_BRONZE_DATASET (default tickvault_bronze), BQ_BRONZE_TABLE (default tickvault_bronze)
# The caller principal must have BigQuery admin on the dataset and Storage Object Viewer on the bucket.
#
# Usage:
#   export GCP_PROJECT_ID=my-project
#   export GCS_BUCKET=my-bucket
#   ./infra/bigquery/apply_bronze_external_table.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
fi

if ! command -v bq >/dev/null 2>&1; then
  echo "bq not found (BigQuery CLI). Install with: gcloud components install bq" >&2
  exit 1
fi

project="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
_raw="${GCS_BUCKET:?Set GCS_BUCKET (bucket name only, no gs:// prefix)}"
_raw="${_raw#"${_raw%%[![:space:]]*}"}"
_raw="${_raw%"${_raw##*[![:space:]]}"}"
bucket="${_raw#gs://}"
dataset="${BQ_BRONZE_DATASET:-tickvault_bronze}"
table="${BQ_BRONZE_TABLE:-tickvault_bronze}"
fqtn="${project}.${dataset}.${table}"

echo "Applying external table ${fqtn} -> gs://${bucket}/bronze/* ..."

bq query --use_legacy_sql=false --project_id="${project}" <<EOF
CREATE OR REPLACE EXTERNAL TABLE \`${project}.${dataset}.${table}\`
(
  stream_kind STRING,
  payload STRING,
  event_ts_ms INT64,
  ingest_ts STRING,
  kafka_topic STRING,
  kafka_partition INT64,
  kafka_offset INT64,
  kafka_ts TIMESTAMP
)
WITH PARTITION COLUMNS
(
  dt STRING,
  symbol STRING,
  exchange STRING
)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://${bucket}/bronze/*'],
  hive_partition_uri_prefix = 'gs://${bucket}/bronze',
  require_hive_partition_filter = FALSE
);
EOF

echo "OK: ${fqtn}"
