#!/bin/sh
# Render Grafana provisioning then exec upstream Grafana entrypoint.
# BigQuery JWT private key is read from /etc/grafana/sa.json (mount keys/gcs.json);
# GCP_PROJECT_ID / GCP_CLIENT_EMAIL / GCP_TOKEN_URI come from the environment (.env).

set -e
mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /etc/grafana/provisioning/alerting

if [ ! -r /etc/grafana/sa.json ]; then
  echo "tickvault-entrypoint: missing /etc/grafana/sa.json (compose should mount ./keys/gcs.json)." >&2
  exit 1
fi

pem=$(mktemp)
trap 'rm -f "$pem"' EXIT
jq -r .private_key /etc/grafana/sa.json > "$pem"

awk -v p="$GCP_PROJECT_ID" -v e="$GCP_CLIENT_EMAIL" -v t="$GCP_TOKEN_URI" -v pemfile="$pem" '
function rep(s, a, b,    i, out) {
  if (length(a) == 0) return s
  out = ""
  while ((i = index(s, a)) > 0) {
    out = out substr(s, 1, i - 1) b
    s = substr(s, i + length(a))
  }
  return out s
}
/^        @TICKVAULT_PEM@$/ {
  while ((getline line < pemfile) > 0) print "        " line
  close(pemfile)
  next
}
{
  s = $0
  s = rep(s, "__GCP_PROJECT__", p)
  s = rep(s, "__GCP_CLIENT_EMAIL__", e)
  s = rep(s, "__GCP_TOKEN_URI__", t)
  print s
}' /etc/grafana/tickvault-templates/bq-datasource.yaml > /etc/grafana/provisioning/datasources/bq.yaml

cp /etc/grafana/tickvault-templates/dashboards.yaml /etc/grafana/provisioning/dashboards/tickvault.yaml
sed -e "s/__GCP_PROJECT__/${GCP_PROJECT_ID}/g" -e "s/__GOLD_DATASET__/${GOLD_DATASET}/g" -e "s/__DLQ_ALERT_THRESHOLD__/${DLQ_ALERT_THRESHOLD}/g" /etc/grafana/tickvault-templates/alerting.yaml > /etc/grafana/provisioning/alerting/tickvault-alerting.yaml

exec /run.sh "$@"
