#!/usr/bin/env bash
# Run dbt debug, build (models), and tests. Loads ../.env if present (set -a).
#
# Set DBT_PROFILES_DIR to this repo's dbt/ folder if you keep profiles.yml next to dbt_project.yml.
# Otherwise uses ~/.dbt/profiles.yml.
#
# Usage:
#   ./scripts/dbt_build.sh
#   ./scripts/dbt_build.sh --select fct_market_metrics
#   STRICT_DBT_FRESHNESS=1 ./scripts/dbt_build.sh   # fail if source freshness is stale

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

# dbt-bigquery with method=oauth can fail with opaque adapter errors when
# Application Default Credentials are missing/expired. Fail early with a
# clear instruction before invoking dbt debug/build.
if [[ -f "${DBT_PROFILES_DIR:-${root}/dbt}/profiles.yml" ]] && grep -qE "method:[[:space:]]*oauth" "${DBT_PROFILES_DIR:-${root}/dbt}/profiles.yml"; then
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud is required for dbt oauth auth. Install Google Cloud SDK or switch dbt profile target to service-account." >&2
    exit 1
  fi
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Missing or expired Application Default Credentials for dbt oauth target.
Run:
  gcloud auth application-default login
Optional (recommended):
  gcloud auth application-default set-quota-project "${GCP_PROJECT_ID:-<your-project-id>}"
Then rerun ./scripts/dbt_build.sh.
EOF
    exit 1
  fi
fi

# Preflight bronze source existence so `dbt source freshness` does not fail
# with a less actionable adapter/database error.
if command -v bq >/dev/null 2>&1; then
  bq_project="${GCP_PROJECT_ID:-}"
  bronze_dataset="${BQ_BRONZE_DATASET:-tickvault_bronze}"
  bronze_table="${BQ_BRONZE_TABLE:-tickvault_bronze}"
  if [[ -n "${bq_project}" ]]; then
    if ! bq show --format=prettyjson "${bq_project}:${bronze_dataset}.${bronze_table}" >/dev/null 2>&1; then
      cat >&2 <<EOF
Missing BigQuery bronze source table:
  ${bq_project}:${bronze_dataset}.${bronze_table}

Create/refresh it first:
  ./scripts/phase2_gcp_bootstrap.sh

If your table uses different names, set:
  BQ_BRONZE_DATASET
  BQ_BRONZE_TABLE
EOF
      exit 1
    fi
  fi
fi

cd "${root}/dbt"

dbt deps
dbt debug
if [[ "${STRICT_DBT_FRESHNESS:-0}" == "1" ]]; then
  dbt source freshness
else
  # Local/dev runs often have gaps in incoming bronze data. Keep freshness
  # visible but do not block model builds unless strict mode is requested.
  dbt source freshness || echo "Warning: source freshness check failed/stale; continuing (set STRICT_DBT_FRESHNESS=1 to fail)." >&2
fi
dbt build "$@"
