#!/usr/bin/env bash
# Scheduler-friendly dbt: deps + run (no dbt debug, no blocking freshness gate).
# Use ./scripts/dbt_build.sh for interactive full checks.
#
# Usage:
#   ./scripts/dbt_run_pipeline.sh
#   ./scripts/dbt_run_pipeline.sh --select fct_market_metrics

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
fi

if [[ -f "${root}/dbt/profiles.yml" ]]; then
  export DBT_PROFILES_DIR="${DBT_PROFILES_DIR:-${root}/dbt}"
fi

if [[ -f "${DBT_PROFILES_DIR:-${root}/dbt}/profiles.yml" ]] && grep -qE "method:[[:space:]]*oauth" "${DBT_PROFILES_DIR:-${root}/dbt}/profiles.yml"; then
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud is required for dbt oauth target." >&2
    exit 1
  fi
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "Missing Application Default Credentials. Run: gcloud auth application-default login" >&2
    exit 1
  fi
fi

if command -v bq >/dev/null 2>&1; then
  bq_project="${GCP_PROJECT_ID:-}"
  bronze_dataset="${BQ_BRONZE_DATASET:-tickvault_bronze}"
  bronze_table="${BQ_BRONZE_TABLE:-tickvault_bronze}"
  if [[ -n "${bq_project}" ]]; then
    if ! bq show --format=prettyjson "${bq_project}:${bronze_dataset}.${bronze_table}" >/dev/null 2>&1; then
      cat >&2 <<EOF
Missing BigQuery bronze source: ${bq_project}:${bronze_dataset}.${bronze_table}
Run: ./infra/bigquery/apply_bronze_external_table.sh (after GCS sync) or Terraform.
EOF
      exit 1
    fi
  fi
fi

cd "${root}/dbt"
dbt deps
dbt run "$@"
