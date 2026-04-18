#!/usr/bin/env bash
set -euo pipefail

host="${FLINK_JOBMANAGER_HOST:-flink-jobmanager}"
port="${FLINK_JOBMANAGER_REST_PORT:-8081}"
job="${BRONZE_JOB_ENTRY:-/opt/flink/usrlib/python/flink_jobs/bronze_sink_job.py}"

echo "Waiting for Flink REST at http://${host}:${port} ..."
for _ in $(seq 1 90); do
  if curl -fsS "http://${host}:${port}/v1/overview" >/dev/null 2>&1; then
    echo "Flink is up."
    break
  fi
  sleep 2
done

if ! curl -fsS "http://${host}:${port}/v1/overview" >/dev/null 2>&1; then
  echo "Flink REST did not become ready in time." >&2
  exit 1
fi

exec /opt/flink/bin/flink run -d \
  -m "${host}:${port}" \
  -pyclientexec /usr/bin/python3 \
  -pyexec /usr/bin/python3 \
  -py "${job}"
