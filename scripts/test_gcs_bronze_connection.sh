#!/usr/bin/env bash
# Verify GCS bucket access and list recent bronze objects using vars from repo .env (or the shell).
# Reads: GCP_PROJECT_ID, GCS_BUCKET (whitespace trimmed). Optional: GCS_PREFIX (default bronze).
#
# Requires: gcloud (recommended) or gsutil, and credentials with storage.buckets.get + storage.objects.list.
#
# Usage (from repo root):
#   ./scripts/test_gcs_bronze_connection.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
fi

trim_ws() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

project=$(trim_ws "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID in .env or export it}")
bucket=$(trim_ws "${GCS_BUCKET:?Set GCS_BUCKET in .env or export it}")
bucket="${bucket#gs://}"
prefix=$(trim_ws "${GCS_PREFIX:-bronze}")

echo "Project: $project"
echo "Bucket:  gs://$bucket"
echo "Prefix:  $prefix/"
echo ""

if command -v gcloud >/dev/null 2>&1; then
  echo "== Bucket metadata (gcloud) =="
  gcloud storage buckets describe "gs://${bucket}" --format="table(name,location,storageClass)" || {
    echo "FAILED: cannot describe bucket (check name, permissions, and billing)." >&2
    exit 1
  }
  echo ""
  echo "== Objects under gs://${bucket}/${prefix}/ (recursive, first 40 lines) =="
  if gcloud storage ls --recursive "gs://${bucket}/${prefix}/" 2>/dev/null | head -40; then
    count=$(gcloud storage ls --recursive "gs://${bucket}/${prefix}/" 2>/dev/null | wc -l | tr -d ' ')
    echo ""
    echo "Listed object path lines (recursive): $count"
    if [[ "${count}" == "0" ]]; then
      echo "No objects yet under gs://${bucket}/${prefix}/ — run ./scripts/sync_bronze_minio_to_gcs.sh after MinIO has Parquet, or sink Flink directly to GCS." >&2
    fi
  else
    echo "(No objects matched, or prefix empty — try: gcloud storage ls gs://${bucket}/ )"
    gcloud storage ls "gs://${bucket}/" 2>/dev/null | head -20 || true
  fi
elif command -v gsutil >/dev/null 2>&1; then
  echo "== Bucket check (gsutil) =="
  gsutil ls -L -b "gs://${bucket}" | head -20
  echo ""
  echo "== Objects (gsutil) =="
  gsutil ls "gs://${bucket}/${prefix}/**" 2>/dev/null | head -40 || gsutil ls "gs://${bucket}/" | head -20
else
  echo "Install Google Cloud SDK (gcloud / gsutil)." >&2
  exit 1
fi

echo ""
echo "OK: GCS reachable with current credentials."
