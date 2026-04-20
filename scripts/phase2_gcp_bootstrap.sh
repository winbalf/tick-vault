#!/usr/bin/env bash
# Create BigQuery datasets (bronze / silver / gold) and the bronze external table on GCS.
# Does not upload Parquet. Run scripts/sync_bronze_minio_to_gcs.sh only when bronze Parquet
# is on MinIO and not yet on GCS; skip sync if Flink already writes to gs:// or the prefix is ready.
#
# Requires: bq, GCP_PROJECT_ID, GCS_BUCKET (bucket name used in the external table URI)
# Optional: BQ_LOCATION (passed to apply_datasets.sh)
#
# Usage:
#   export GCP_PROJECT_ID=my-project
#   export GCS_BUCKET=my-bucket
#   ./scripts/phase2_gcp_bootstrap.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
fi

"${root}/infra/bigquery/apply_datasets.sh"
"${root}/infra/bigquery/apply_bronze_external_table.sh"

echo "Phase 2 BigQuery bootstrap complete."
