#!/usr/bin/env bash
# One-shot pipeline checks: Kafka sample, Flink jobs, MinIO bronze objects, optional BigQuery gold row count.
#
# Run from repo root (uses docker compose for Redpanda when the stack is up):
#   ./scripts/pipeline_health.sh
#
# Environment (optional; repo .env is sourced when present):
#   TRADES_TOPIC           default raw.trades.v1
#   KAFKA_SAMPLE_N         default 2
#   FLINK_REST             default http://localhost:8081
#   MINIO_ENDPOINT         default http://127.0.0.1:9000
#   MINIO_ALIAS_BUCKET     default local/tick-vault/bronze
#   MINIO_ACCESS_KEY       default minioadmin
#   MINIO_SECRET_KEY       default minioadmin
#   GCP_PROJECT_ID         for optional BigQuery check
#   GOLD_DATASET           default tickvault_gold
#   GOOGLE_APPLICATION_CREDENTIALS — if set and bq exists, run gold mart count
#   PIPELINE_HEALTH_SKIP_BQ=1 — never run bq

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
fi

set +e

TRADES_TOPIC="${TRADES_TOPIC:-raw.trades.v1}"
KAFKA_SAMPLE_N="${KAFKA_SAMPLE_N:-2}"
FLINK_REST="${FLINK_REST:-http://localhost:8081}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://127.0.0.1:9000}"
MINIO_ALIAS_BUCKET="${MINIO_ALIAS_BUCKET:-local/tick-vault/bronze}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"
GOLD_DATASET="${GOLD_DATASET:-tickvault_gold}"

fail=0

echo "== tick-vault pipeline health ($(date -u +%Y-%m-%dT%H:%M:%SZ)) =="
echo ""

echo "== Kafka: last ${KAFKA_SAMPLE_N} message(s) on ${TRADES_TOPIC} =="
if docker compose ps redpanda --status running -q 2>/dev/null | grep -q .; then
  if out=$(docker compose exec -T redpanda rpk topic consume "${TRADES_TOPIC}" -n "${KAFKA_SAMPLE_N}" -o :end 2>&1); then
    echo "$out" | head -c 4000
    if [[ "$(echo "$out" | wc -l)" -lt 1 ]]; then
      echo "(no lines returned)" >&2
      fail=1
    fi
  else
    echo "rpk consume failed: $out" >&2
    fail=1
  fi
elif command -v rpk >/dev/null 2>&1; then
  export RPK_BROKERS="${RPK_BROKERS:-127.0.0.1:19092}"
  if ! rpk topic consume "${TRADES_TOPIC}" -n "${KAFKA_SAMPLE_N}" -o :end 2>&1 | head -c 4000; then
    echo "rpk on host failed (set RPK_BROKERS or start Redpanda)." >&2
    fail=1
  fi
else
  echo "Redpanda container not running and rpk not on PATH; skipping Kafka sample." >&2
  fail=1
fi
echo ""

echo "== Flink: jobs from ${FLINK_REST}/jobs/overview =="
flink_json=""
if flink_json=$(curl -fsS --max-time 5 "${FLINK_REST}/jobs/overview" 2>&1); then
  if command -v python3 >/dev/null 2>&1; then
    if ! printf '%s' "$flink_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print('Invalid JSON from Flink:', e, file=sys.stderr)
    sys.exit(1)
jobs = data.get('jobs') or []
running = [j for j in jobs if j.get('state') == 'RUNNING']
if not jobs:
    print('(no jobs returned)')
else:
    for j in jobs[:12]:
        st, nm = j.get('state', '?'), j.get('name', '')
        print(f'  {st:10}  {nm}')
    if len(jobs) > 12:
        print(f'  ... and {len(jobs) - 12} more')
if not running:
    print('No RUNNING Flink jobs.', file=sys.stderr)
    sys.exit(1)
"; then
      fail=1
    fi
  else
    echo "$flink_json" | head -c 2000
    echo "(install python3 for structured Flink summary)" >&2
  fi
else
  echo "curl failed: $flink_json" >&2
  fail=1
fi
echo ""

echo "== MinIO: object count under ${MINIO_ALIAS_BUCKET} =="
mc_img="minio/mc:RELEASE.2024-08-26T10-49-58Z"
mc_tmp="$(mktemp)"
if docker run --rm --network host --entrypoint /bin/sh "${mc_img}" -c \
  "mc alias set local ${MINIO_ENDPOINT} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} >/dev/null 2>&1 && mc ls -r ${MINIO_ALIAS_BUCKET} 2>/dev/null" \
  >"$mc_tmp" 2>/dev/null; then
  cnt=$(wc -l <"$mc_tmp" | tr -d ' ')
  rm -f "$mc_tmp"
  echo "  objects listed: ${cnt:-0}"
  if [[ "${cnt:-0}" -eq 0 ]]; then
    echo "  (no objects — is MinIO up and Flink writing bronze?)" >&2
    fail=1
  fi
else
  echo "  mc listing failed (is MinIO reachable at ${MINIO_ENDPOINT}?)" >&2
  rm -f "$mc_tmp"
  fail=1
fi
echo ""

echo "== BigQuery (optional): recent rows in ${GOLD_DATASET}.fct_market_metrics =="
if [[ "${PIPELINE_HEALTH_SKIP_BQ:-}" == "1" ]]; then
  echo "  skipped (PIPELINE_HEALTH_SKIP_BQ=1)"
elif ! command -v bq >/dev/null 2>&1; then
  echo "  skipped (bq not on PATH)"
elif [[ -z "${GCP_PROJECT_ID:-}" ]]; then
  echo "  skipped (GCP_PROJECT_ID unset)"
elif [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && ! -r "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
  echo "  skipped (GOOGLE_APPLICATION_CREDENTIALS not readable: ${GOOGLE_APPLICATION_CREDENTIALS})" >&2
else
  sql="SELECT COUNT(*) AS n FROM \`${GCP_PROJECT_ID}.${GOLD_DATASET}.fct_market_metrics\` WHERE metric_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)"
  if bq_out=$(bq query --project_id="${GCP_PROJECT_ID}" --nouse_legacy_sql --format=csv "${sql}" 2>&1); then
    echo "$bq_out" | sed 's/^/  /'
  else
    echo "  bq query failed:" >&2
    echo "$bq_out" | sed 's/^/  /' >&2
  fi
fi
echo ""

if [[ "$fail" -ne 0 ]]; then
  echo "Done with failures (Kafka / Flink / MinIO). Fix stack or connectivity and re-run." >&2
  exit 1
fi
echo "All required checks passed."
