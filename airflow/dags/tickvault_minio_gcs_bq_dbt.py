"""
Tick Vault — batch lane after bronze lands in MinIO.

Tasks:
  1. sync_minio_to_gcs — mirror bronze Parquet to gs://$GCS_BUCKET/bronze/
  2. refresh_bronze_external_table — BigQuery CREATE OR REPLACE external table (Hive partitions)
  3. dbt_run — dbt deps + dbt run (silver/gold)

Environment (set in docker-compose or Airflow Variables / Connections as needed):
  TICKVAULT_ROOT — repo root (default /opt/airflow/tickvault in Docker Compose)
  GCP_PROJECT_ID, GCS_BUCKET, MINIO_ENDPOINT — same semantics as host scripts
  GOOGLE_APPLICATION_CREDENTIALS or ~/.config/gcloud (CLOUDSDK_CONFIG in compose)
"""

from __future__ import annotations

import os
from datetime import timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from pendulum import datetime

ROOT = os.environ.get("TICKVAULT_ROOT", "/opt/airflow/tickvault")

default_args = {
    "owner": "tick-vault",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

schedule = os.environ.get("TICKVAULT_AIRFLOW_SCHEDULE", "@hourly")
if schedule.lower() in ("", "none", "null"):
    schedule = None

with DAG(
    dag_id="tickvault_minio_gcs_bq_dbt",
    default_args=default_args,
    schedule=schedule,
    start_date=datetime(2024, 1, 1, tz="UTC"),
    catchup=False,
    tags=["tick-vault", "gcs", "bigquery", "dbt"],
    doc_md=__doc__,
) as dag:
    sync = BashOperator(
        task_id="sync_minio_to_gcs",
        bash_command=(
            f'set -euo pipefail && cd "{ROOT}" && ./scripts/sync_bronze_minio_to_gcs.sh'
        ),
    )

    refresh = BashOperator(
        task_id="refresh_bronze_external_table",
        bash_command=(
            f'set -euo pipefail && cd "{ROOT}" && ./infra/bigquery/apply_bronze_external_table.sh'
        ),
    )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=(
            f'set -euo pipefail && cd "{ROOT}" && ./scripts/dbt_run_pipeline.sh'
        ),
    )

    sync >> refresh >> dbt_run
