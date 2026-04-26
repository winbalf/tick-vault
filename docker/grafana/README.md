# Grafana (Tick Vault)

The Compose service `grafana` (profile `grafana`) installs the official **BigQuery** data source plugin, provisions the datasource, auto-loads dashboards from `docker/grafana/dashboards`, and provisions alert rules.

1. Start with a real project id and JWT settings in `.env` or your shell:
   - `export GCP_PROJECT_ID=...`
   - `export GCP_CLIENT_EMAIL=service-account@<project>.iam.gserviceaccount.com`
   - `export GCP_TOKEN_URI=https://oauth2.googleapis.com/token`
   - `export GCP_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"`
2. `docker compose --profile grafana up -d grafana` (other services optional).
3. Open `http://localhost:3000`. Admin login is `admin` / `GF_ADMIN_PASSWORD` (default `admin`). Anonymous access is enabled with **Admin** org role so you can finish the BigQuery datasource without logging in—**do not expose this profile to the internet**.
4. BigQuery datasource is provisioned in minimal JWT mode (`authenticationType`, `defaultProject`, `clientEmail`, `tokenUri`, `privateKey`).
5. Configure optional `.env` values:
   - `GCP_CLIENT_EMAIL` (service account email)
   - `GCP_TOKEN_URI` (default `https://oauth2.googleapis.com/token`)
   - `GCP_PRIVATE_KEY` (escaped PEM with `\n`)
   - `GOLD_DATASET` (default `tickvault_gold`)
   - `DLQ_ALERT_THRESHOLD` (default `25`)
6. Stack is pinned to a known-compatible combo for this plugin generation:
   - `grafana/grafana:11.6.2`
   - `grafana-bigquery-datasource 3.1.5`
7. Dashboards auto-provisioned from code:
   - `Tick Vault — Live Price & Volume`
   - `Tick Vault — Spread & VWAP`
   - `Tick Vault — Volatility Heatmap`
   - `Tick Vault — Pipeline Health`
8. A Grafana alert rule `DLQ count above threshold` is provisioned and evaluates every minute against the last 5 minutes of data.
