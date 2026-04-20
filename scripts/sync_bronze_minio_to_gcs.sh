#!/usr/bin/env bash
# Mirror Hive-partitioned bronze Parquet from local MinIO to GCS so BigQuery external tables work.
#
# Requires:
#   - gcloud auth with storage scope (Application Default Credentials or gcloud auth login)
#     — not required if the mirror is empty and SKIP_GCS_UPLOAD_IF_NO_PARQUET=1
#   - GCS_BUCKET in repo .env or: export GCS_BUCKET=your-bucket-name   (objects land under gs://$GCS_BUCKET/bronze/...)
# Mirror (one of):
#   - Docker (default): Docker + minio/mc image
#   - USE_LOCAL_MC=1: mc on PATH (e.g. docker/gcs-pipeline container)
# Optional:
#   MINIO_ENDPOINT (default http://127.0.0.1:9000) — host must reach MinIO (compose exposes 9000)
#   DOCKER_MC_NETWORK (default host) — docker network for the mc container when USE_LOCAL_MC is unset
#   MINIO_ACCESS_KEY / MINIO_SECRET_KEY (default minioadmin / minioadmin)
#   STAGING_DIR (default a temp dir under /tmp)
#   SKIP_GCS_UPLOAD_IF_NO_PARQUET=1 — after mirror, if no *.parquet, skip GCS upload and exit 0
#
# Usage:
#   export GCS_BUCKET=my-bucket
#   ./scripts/sync_bronze_minio_to_gcs.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -f "${root}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root}/.env"
  set +a
fi

_raw_bucket="${GCS_BUCKET:?Set GCS_BUCKET in .env or export it (destination bucket, no gs:// prefix)}"
_raw_bucket="${_raw_bucket#"${_raw_bucket%%[![:space:]]*}"}"
_raw_bucket="${_raw_bucket%"${_raw_bucket##*[![:space:]]}"}"
bucket="${_raw_bucket#gs://}"

endpoint="${MINIO_ENDPOINT:-http://127.0.0.1:9000}"
access="${MINIO_ACCESS_KEY:-minioadmin}"
secret="${MINIO_SECRET_KEY:-minioadmin}"
staging="${STAGING_DIR:-$(mktemp -d -t tickvault-bronze-sync.XXXXXX)}"

cleanup() {
  if [[ "${KEEP_STAGING:-}" == "1" ]] || [[ -z "${staging}" ]] || [[ ! -d "${staging}" ]]; then
    return 0
  fi
  if rm -rf "${staging}" 2>/dev/null; then
    return 0
  fi
  # mc in Docker defaults to root: mirrored files on the bind mount can be root-owned.
  if command -v docker >/dev/null 2>&1; then
    docker run --rm -v "${staging}:/out" busybox:musl rm -rf /out/bronze >/dev/null 2>&1 || true
    rmdir "${staging}" 2>/dev/null || true
  fi
  rm -rf "${staging}" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "${staging}/bronze"
echo "Staging mirror under ${staging}/bronze (from MinIO ${endpoint})..."

if [[ "${USE_LOCAL_MC:-}" == "1" ]]; then
  if ! command -v mc >/dev/null 2>&1; then
    echo "USE_LOCAL_MC=1 but mc is not on PATH." >&2
    exit 1
  fi
  mc alias set local "${endpoint}" "${access}" "${secret}"
  mc mirror --overwrite --remove local/tick-vault/bronze "${staging}/bronze"
else
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found." >&2
    exit 1
  fi
  net="${DOCKER_MC_NETWORK:-host}"
  # Run as the invoking user so bind-mounted files are removable without root; MC_CONFIG_DIR avoids ~/.mc permission issues.
  # minio/mc image ENTRYPOINT is `mc`, so we must use --entrypoint /bin/sh to run two mc invocations.
  docker run --rm --user "$(id -u):$(id -g)" --network "${net}" \
    -e MC_CONFIG_DIR=/tmp/mcconfig \
    -e HOME=/tmp \
    -v "${staging}:/out" \
    --entrypoint /bin/sh \
    minio/mc:RELEASE.2024-08-26T10-49-58Z \
    -c "mc alias set local '${endpoint}' '${access}' '${secret}' && mc mirror --overwrite --remove local/tick-vault/bronze /out/bronze"
fi

# Flink/Spark often write Parquet as part-* without a .parquet suffix.
if [[ ! -d "${staging}/bronze" ]] || [[ -z "$(find "${staging}/bronze" -type f \( -name '*.parquet' -o -name 'part-*' \) 2>/dev/null | head -1)" ]]; then
  echo "Warning: no bronze data files found (*.parquet or part-*) under ${staging}/bronze. Is MinIO populated and Flink bronze job running?" >&2
  if [[ "${SKIP_GCS_UPLOAD_IF_NO_PARQUET:-}" == "1" ]]; then
    echo "SKIP_GCS_UPLOAD_IF_NO_PARQUET=1: skipping GCS upload."
    exit 0
  fi
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found. Install Google Cloud SDK." >&2
  exit 1
fi

echo "Uploading to gs://${bucket}/bronze/ ..."
if gcloud storage rsync --help >/dev/null 2>&1; then
  gcloud storage rsync "${staging}/bronze" "gs://${bucket}/bronze" --recursive
elif command -v gsutil >/dev/null 2>&1; then
  gsutil -m rsync -r "${staging}/bronze" "gs://${bucket}/bronze"
else
  echo "Neither 'gcloud storage rsync' nor gsutil is available. Install Google Cloud SDK." >&2
  exit 1
fi

echo "Done. Next: ./infra/bigquery/apply_bronze_external_table.sh (with same GCS_BUCKET and GCP_PROJECT_ID)."
