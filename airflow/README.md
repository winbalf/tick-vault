# Airflow — Tick Vault batch lane

This folder adds a **minimal Apache Airflow** stack that runs the same three steps as the manual GCP path:

1. **MinIO → GCS** — `scripts/sync_bronze_minio_to_gcs.sh` (uses Docker + `minio/mc` against `MINIO_ENDPOINT`, then `gcloud storage rsync`).
2. **Refresh bronze external table** — `infra/bigquery/apply_bronze_external_table.sh` (`CREATE OR REPLACE` so Hive partitions are registered).
3. **dbt** — `scripts/dbt_run_pipeline.sh` (`dbt deps` + `dbt run`).

The DAG file is `dags/tickvault_minio_gcs_bq_dbt.py` (`dag_id`: `tickvault_minio_gcs_bq_dbt`).

## Prerequisites

- Repo **`.env`** (or exported vars) with at least **`GCP_PROJECT_ID`** and **`GCS_BUCKET`**.
- **MinIO** with bronze data, reachable from the host at **`MINIO_ENDPOINT`** (default `http://127.0.0.1:9000`). Start the main stack first: `docker compose up -d` from the repo root.
- **Google ADC** on the host: `~/.config/gcloud` is bind-mounted read-only (`CLOUDSDK_CONFIG` inside the container). Alternatively set **`GOOGLE_APPLICATION_CREDENTIALS`** in `.env` to an absolute path inside the mounted repo (for example `/opt/airflow/tick-vault/keys/your.json`).
- **Docker socket** mounted so the sync script can run `minio/mc` with host networking to reach MinIO.

## Start Airflow

From the **repository root**:

```bash
export DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"   # Linux / WSL
# macOS: export DOCKER_GID="$(stat -f '%g' /var/run/docker.sock)"

docker compose -f airflow/docker-compose.yml up --build -d
```

- **Web UI:** [http://localhost:8085](http://localhost:8085) — user **`admin`**, password **`admin`** (change after first login).
- **Pause/unpause** the DAG in the UI as needed.

## Schedule

By default the DAG uses **`@hourly`**. Override before `up`:

```bash
export TICKVAULT_AIRFLOW_SCHEDULE=None   # manual triggers only (Airflow 2.7+)
```

Or edit `airflow/dags/tickvault_minio_gcs_bq_dbt.py`.

## Security note

This setup is for **local / lab** use: the Airflow image joins the **Docker** group on the host via `group_add` and mounts **`/var/run/docker.sock`**. Do not expose this compose file unchanged to the public internet.

## Optional: install Airflow on the host

If you already run Airflow elsewhere, copy or symlink `airflow/dags/tickvault_minio_gcs_bq_dbt.py` into your `AIRFLOW_HOME/dags`, set **`TICKVAULT_ROOT`** to this repo’s absolute path, install **`dbt-bigquery`** and the **Google Cloud SDK** on workers, and ensure workers can run Docker (for sync) or run the sync step on a box that can.
