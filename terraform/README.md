# Terraform — GCP bucket, BigQuery medallion datasets, bronze external table

This directory provisions:

- A **GCS bucket** (bronze objects are expected under `gs://<bucket>/bronze/…` — same layout as Flink / MinIO sync).
- **BigQuery datasets** `tickvault_bronze`, `tickvault_silver`, `tickvault_gold` (names overridable via variables).
- Optionally the **bronze Hive-partitioned external table** (same schema as `infra/bigquery/apply_bronze_external_table.sh`).
- **IAM** (optional): grants `roles/storage.objectAdmin` on the bucket and `roles/bigquery.dataEditor` on the three datasets plus `roles/bigquery.jobUser` on the project for `pipeline_service_account_email` (leave empty to manage IAM manually).
- **`roles/storage.objectViewer`** on the bucket for the **GCS service account** used by BigQuery when reading external tables (`data.google_storage_project_service_account`).

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set project_id, bucket_name, etc.

terraform init
terraform plan
terraform apply
```

After apply, set **`GCS_BUCKET`** in the repo `.env` to the output **`gcs_bucket_name`**, then run the streaming stack and sync scripts (or Airflow DAG) as usual.

## Variables

See `variables.tf`. Common toggles:

- **`create_bronze_external_table`** — set `false` if you only want bucket + datasets and prefer shell DDL (`apply_bronze_external_table.sh`).
- **`pipeline_service_account_email`** — dbt or Airflow workload identity / SA email for dataset + bucket access.
- **`enable_project_apis`** — set `true` once if APIs are not already enabled (needs billing / org policy).

## State

No remote backend is configured by default; state is **local** `terraform.tfstate`. Add a `backend "gcs" {}` block when you are ready for shared state.
