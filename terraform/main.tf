resource "google_project_service" "required" {
  for_each = var.enable_project_apis ? toset([
    "storage.googleapis.com",
    "bigquery.googleapis.com",
  ]) : toset([])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

resource "google_storage_bucket" "tickvault" {
  name                        = var.bucket_name
  location                    = var.bucket_location
  project                     = var.project_id
  force_destroy               = var.bucket_force_destroy
  uniform_bucket_level_access = true

  depends_on = [google_project_service.required]
}

resource "google_bigquery_dataset" "bronze" {
  dataset_id                 = var.bronze_dataset_id
  project                    = var.project_id
  location                   = var.bq_location
  delete_contents_on_destroy = false

  depends_on = [google_project_service.required]
}

resource "google_bigquery_dataset" "silver" {
  dataset_id                 = var.silver_dataset_id
  project                    = var.project_id
  location                   = var.bq_location
  delete_contents_on_destroy = false

  depends_on = [google_project_service.required]
}

resource "google_bigquery_dataset" "gold" {
  dataset_id                 = var.gold_dataset_id
  project                    = var.project_id
  location                   = var.bq_location
  delete_contents_on_destroy = false

  depends_on = [google_project_service.required]
}

locals {
  bronze_uri_prefix = "gs://${google_storage_bucket.tickvault.name}/bronze"
  bronze_uris       = ["gs://${google_storage_bucket.tickvault.name}/bronze/*"]
}

resource "google_bigquery_table" "bronze_external" {
  count = var.create_bronze_external_table ? 1 : 0

  dataset_id = google_bigquery_dataset.bronze.dataset_id
  project    = var.project_id
  table_id   = var.bronze_external_table_id

  external_data_configuration {
    autodetect    = false
    source_format = "PARQUET"
    source_uris   = local.bronze_uris

    hive_partitioning_options {
      mode                     = "AUTO"
      source_uri_prefix        = local.bronze_uri_prefix
      require_partition_filter = false
    }

    schema = jsonencode([
      { name = "stream_kind", type = "STRING", mode = "NULLABLE" },
      { name = "payload", type = "STRING", mode = "NULLABLE" },
      { name = "event_ts_ms", type = "INTEGER", mode = "NULLABLE" },
      { name = "ingest_ts", type = "STRING", mode = "NULLABLE" },
      { name = "kafka_topic", type = "STRING", mode = "NULLABLE" },
      { name = "kafka_partition", type = "INTEGER", mode = "NULLABLE" },
      { name = "kafka_offset", type = "INTEGER", mode = "NULLABLE" },
      { name = "kafka_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    ])
  }

  depends_on = [google_bigquery_dataset.bronze, google_storage_bucket.tickvault]
}

data "google_storage_project_service_account" "gcs_sa" {
  project = var.project_id
}

resource "google_storage_bucket_iam_member" "bigquery_gcs_object_viewer" {
  bucket = google_storage_bucket.tickvault.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
}

resource "google_storage_bucket_iam_member" "pipeline_object_admin" {
  count  = var.pipeline_service_account_email == "" ? 0 : 1
  bucket = google_storage_bucket.tickvault.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.pipeline_service_account_email}"
}

resource "google_bigquery_dataset_iam_member" "pipeline_bronze_editor" {
  count      = var.pipeline_service_account_email == "" ? 0 : 1
  dataset_id = google_bigquery_dataset.bronze.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.pipeline_service_account_email}"
}

resource "google_bigquery_dataset_iam_member" "pipeline_silver_editor" {
  count      = var.pipeline_service_account_email == "" ? 0 : 1
  dataset_id = google_bigquery_dataset.silver.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.pipeline_service_account_email}"
}

resource "google_bigquery_dataset_iam_member" "pipeline_gold_editor" {
  count      = var.pipeline_service_account_email == "" ? 0 : 1
  dataset_id = google_bigquery_dataset.gold.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.pipeline_service_account_email}"
}

resource "google_project_iam_member" "pipeline_bq_job_user" {
  count   = var.pipeline_service_account_email == "" ? 0 : 1
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${var.pipeline_service_account_email}"
}
