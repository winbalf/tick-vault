# Grafana (Tick Vault)

The Compose service `grafana` (profile `grafana`) installs the official **BigQuery** data source plugin and provisions a datasource whose **default project** is taken from `GCP_PROJECT_ID`.

1. Start with a real project id in `.env` or your shell: `export GCP_PROJECT_ID=...`
2. `docker compose --profile grafana up -d grafana` (other services optional).
3. Open `http://localhost:3000`. Admin login is `admin` / `GF_ADMIN_PASSWORD` (default `admin`). Anonymous access is enabled with **Admin** org role so you can finish the BigQuery datasource without logging in—**do not expose this profile to the internet**.
4. **Authenticate BigQuery**: Connections → Data sources → BigQuery → set **Service account** JWT (paste JSON key fields) or use a method your environment supports. Until JWT is set, panels will not load data.
5. On the **Tick Vault** dashboard, set template variables **GCP project** and **Gold dataset** if they differ from defaults.
