#!/usr/bin/env bash
set -euo pipefail

# Repo is bind-mounted at /repo by compose.
cd /repo

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

export USE_LOCAL_MC=1
export MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://minio:9000}"
export SKIP_GCS_UPLOAD_IF_NO_PARQUET="${SKIP_GCS_UPLOAD_IF_NO_PARQUET:-1}"

exec ./scripts/bronze_to_gcs_and_bq.sh
