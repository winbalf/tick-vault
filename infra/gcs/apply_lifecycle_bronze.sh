#!/usr/bin/env bash
set -euo pipefail

# Applies a 90-day retention lifecycle rule scoped to the bronze/ prefix.
# Usage: ./infra/gcs/apply_lifecycle_bronze.sh gs://YOUR_BUCKET
#
# Requires: gcloud CLI authenticated with storage permissions.

bucket="${1:-}"
if [[ -z "${bucket}" ]]; then
  echo "Usage: $0 gs://BUCKET_NAME" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
lifecycle_file="${root}/infra/gcs/lifecycle_bronze_90d.json"

gcloud storage buckets update "${bucket}" --lifecycle-file="${lifecycle_file}"
echo "Lifecycle applied to ${bucket} (delete objects under bronze/ older than 90 days)."
