#!/usr/bin/env bash
# End-to-end helper:
# Docker build/start -> bronze submit -> MinIO->GCS + BQ bootstrap -> dbt build -> Grafana.
#
# Usage:
#   ./scripts/run_end_to_end.sh
#   ./scripts/run_end_to_end.sh --no-build
#   ./scripts/run_end_to_end.sh --no-bronze-submit
#   ./scripts/run_end_to_end.sh --no-grafana
#   ./scripts/run_end_to_end.sh --skip-gcs-test
#   ./scripts/run_end_to_end.sh --force-rsync
#   ./scripts/run_end_to_end.sh --dry-run
#
# This script expects GCP_PROJECT_ID and GCS_BUCKET in .env (or exported).

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

build_core=1
submit_bronze=1
run_gcs_test=1
start_grafana=1
force_rsync=0
dry_run=0

usage() {
  cat <<'EOF'
Usage: ./scripts/run_end_to_end.sh [options]

Options:
  --no-build          Skip `docker compose up --build -d`
  --no-bronze-submit  Skip bronze Flink submit
  --skip-gcs-test     Skip scripts/test_gcs_bronze_connection.sh
  --no-grafana        Skip docker compose --profile grafana up
  --force-rsync       Set SKIP_GCS_UPLOAD_IF_NO_PARQUET=0 for bronze->GCS sync
  --dry-run           Print steps/commands without executing them
  -h, --help          Show this help
EOF
}

run_cmd() {
  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) build_core=0 ;;
    --no-bronze-submit) submit_bronze=0 ;;
    --skip-gcs-test) run_gcs_test=0 ;;
    --no-grafana) start_grafana=0 ;;
    --force-rsync) force_rsync=1 ;;
    --dry-run) dry_run=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
fi

if [[ -z "${GCP_PROJECT_ID:-}" || -z "${GCS_BUCKET:-}" ]]; then
  cat >&2 <<'EOF'
Missing required env vars.
Set GCP_PROJECT_ID and GCS_BUCKET in .env (or export them), then rerun.
EOF
  exit 1
fi

echo "== Tick Vault end-to-end run =="
echo "Project: ${GCP_PROJECT_ID}"
echo "Bucket:  ${GCS_BUCKET}"
echo ""

if [[ "$build_core" == "1" ]]; then
  echo "1/5 Build and start core stack..."
  run_cmd docker compose up --build -d
else
  echo "1/5 Skipped core stack build/start (--no-build)."
fi

if [[ "$submit_bronze" == "1" ]]; then
  echo "2/5 Submit bronze Flink job..."
  run_cmd docker compose up -d minio minio-init redpanda topic-init flink-jobmanager flink-taskmanager
  run_cmd docker compose --profile bronze run --rm flink-submit-bronze
else
  echo "2/5 Skipped bronze submit (--no-bronze-submit)."
fi

echo "3/5 Sync bronze to GCS and bootstrap BigQuery..."
if [[ "$run_gcs_test" == "1" ]]; then
  run_cmd ./scripts/test_gcs_bronze_connection.sh
else
  echo "Skipped GCS connectivity test (--skip-gcs-test)."
fi

if [[ "$force_rsync" == "1" ]]; then
  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] SKIP_GCS_UPLOAD_IF_NO_PARQUET=0 ./scripts/bronze_to_gcs_and_bq.sh"
  else
    SKIP_GCS_UPLOAD_IF_NO_PARQUET=0 ./scripts/bronze_to_gcs_and_bq.sh
  fi
else
  run_cmd ./scripts/bronze_to_gcs_and_bq.sh
fi

echo "4/5 Run dbt build..."
run_cmd ./scripts/dbt_build.sh

if [[ "$start_grafana" == "1" ]]; then
  echo "5/5 Start Grafana..."
  run_cmd docker compose --profile grafana up --build -d grafana
  echo "Grafana: http://localhost:3000"
else
  echo "5/5 Skipped Grafana startup (--no-grafana)."
fi

echo ""
echo "End-to-end run completed."
