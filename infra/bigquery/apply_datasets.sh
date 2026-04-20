#!/usr/bin/env bash
# Create BigQuery datasets tickvault_bronze, tickvault_silver, tickvault_gold if missing.
# Requires: gcloud/bq CLI, and GCP_PROJECT_ID. Uses GOOGLE_APPLICATION_CREDENTIALS or ADC.
#
# Usage:
#   export GCP_PROJECT_ID=your-project-id
#   export BQ_LOCATION=US   # optional; default US (matches dbt profile location)
#   ./infra/bigquery/apply_datasets.sh

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
  echo "bq not found (BigQuery CLI). Add it to PATH, for example:" >&2
  echo "  gcloud components install bq" >&2
  echo "Or use SKIP_BQ_BOOTSTRAP=1 with ./scripts/bronze_to_gcs_and_bq.sh to upload to GCS only." >&2
  exit 1
fi

project="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID to your GCP project id}"
location="${BQ_LOCATION:-US}"

for dataset in tickvault_bronze tickvault_silver tickvault_gold; do
  fqid="${project}:${dataset}"
  if bq show --format=prettyjson "$fqid" >/dev/null 2>&1; then
    echo "OK (already exists): $fqid"
  else
    echo "Creating $fqid (location=$location)..."
    bq --location="$location" mk -d "$fqid"
    echo "Created: $fqid"
  fi
done

echo "Done. List: bq ls --project_id=$project"
