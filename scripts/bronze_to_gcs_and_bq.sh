#!/usr/bin/env bash
# Bronze path: MinIO → GCS (when Parquet exists) + BigQuery datasets and bronze external table.
#
# Intended for:
#   - Host: ./scripts/bronze_to_gcs_and_bq.sh (needs docker, gcloud, bq unless USE_LOCAL_MC + already synced)
#   - Compose profile gcs: docker/gcs-pipeline (USE_LOCAL_MC=1, MINIO_ENDPOINT=http://minio:9000)
#
# Reads repo .env when present. Requires GCP_PROJECT_ID and GCS_BUCKET.
# Optional:
#   GCS_PIPELINE_WAIT_SECONDS — sleep this many seconds before sync (give Flink time after stack up)
#   SKIP_GCS_UPLOAD_IF_NO_PARQUET — default 1 for this script (skip empty upload); set 0 to always rsync
#   SKIP_BQ_BOOTSTRAP=1 — after GCS sync, skip datasets + external table (use when bq is not installed yet)
#
# Usage:
#   ./scripts/bronze_to_gcs_and_bq.sh
#   SKIP_GCS_UPLOAD_IF_NO_PARQUET=0 ./scripts/bronze_to_gcs_and_bq.sh   # force rsync even if mirror is empty

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
fi

if [[ -z "${GCP_PROJECT_ID:-}" || -z "${GCS_BUCKET:-}" ]]; then
  echo "bronze_to_gcs_and_bq.sh: set GCP_PROJECT_ID and GCS_BUCKET (e.g. in .env)." >&2
  exit 1
fi

wait_s="${GCS_PIPELINE_WAIT_SECONDS:-0}"
if [[ "${wait_s}" =~ ^[0-9]+$ ]] && [[ "$wait_s" -gt 0 ]]; then
  echo "Waiting ${wait_s}s (GCS_PIPELINE_WAIT_SECONDS) before MinIO → GCS sync..."
  sleep "$wait_s"
fi

export SKIP_GCS_UPLOAD_IF_NO_PARQUET="${SKIP_GCS_UPLOAD_IF_NO_PARQUET:-1}"

"${root}/scripts/sync_bronze_minio_to_gcs.sh"
if [[ "${SKIP_BQ_BOOTSTRAP:-}" == "1" ]]; then
  echo "SKIP_BQ_BOOTSTRAP=1: skipping BigQuery. When bq is available, run: ./scripts/phase2_gcp_bootstrap.sh" >&2
else
  "${root}/scripts/phase2_gcp_bootstrap.sh"
fi

if [[ "${SKIP_BQ_BOOTSTRAP:-}" == "1" ]]; then
  echo "Bronze GCS sync complete (BigQuery bootstrap skipped)."
else
  echo "Bronze GCS + BigQuery bootstrap complete."
fi
