#!/usr/bin/env bash
# Mirror MinIO bronze Parquet to GCS, then create BQ datasets + bronze external table.
# Same as bronze_to_gcs_and_bq.sh but always attempts GCS upload even when the mirror is empty.
#
# Requires: docker, gcloud/gsutil, GCP_PROJECT_ID, GCS_BUCKET; bq for BigQuery bootstrap (unless skipped).
#
# Usage:
#   export GCP_PROJECT_ID=my-project
#   export GCS_BUCKET=my-bucket
#   ./scripts/phase2_upload_and_bootstrap.sh
#   SKIP_BQ_BOOTSTRAP=1 ./scripts/phase2_upload_and_bootstrap.sh   # GCS only if bq is not installed

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export SKIP_GCS_UPLOAD_IF_NO_PARQUET=0
"${root}/scripts/bronze_to_gcs_and_bq.sh"
