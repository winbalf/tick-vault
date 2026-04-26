#!/usr/bin/env bash
set -euo pipefail

# Repo is bind-mounted at /repo by compose.
cd /repo

# Host ~/.config/gcloud is mounted read-only at /gcloud-ro; gcloud still needs a writable CLOUDSDK_CONFIG
# (credentials.db, logs). Seed from the mount when present.
if [[ -d /gcloud-ro ]]; then
  export CLOUDSDK_CONFIG="${CLOUDSDK_CONFIG:-/tmp/gcloud-config}"
  rm -rf "${CLOUDSDK_CONFIG}"
  mkdir -p "${CLOUDSDK_CONFIG}"
  cp -a /gcloud-ro/. "${CLOUDSDK_CONFIG}/"
fi

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
