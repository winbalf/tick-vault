#!/usr/bin/env bash
# Run dbt debug, build (models), and tests. Loads ../.env if present (set -a).
#
# Set DBT_PROFILES_DIR to this repo's dbt/ folder if you keep profiles.yml next to dbt_project.yml.
# Otherwise uses ~/.dbt/profiles.yml.
#
# Usage:
#   ./scripts/dbt_build.sh
#   ./scripts/dbt_build.sh --select fct_market_metrics

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

cd "${root}/dbt"

dbt debug
dbt build "$@"
