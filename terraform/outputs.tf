output "gcs_bucket_name" {
  description = "Bucket name (set GCS_BUCKET in .env to this value)."
  value       = google_storage_bucket.tickvault.name
}

output "gcs_bronze_prefix" {
  value = local.bronze_uri_prefix
}

output "bigquery_bronze_dataset" {
  value = google_bigquery_dataset.bronze.dataset_id
}

output "bigquery_silver_dataset" {
  value = google_bigquery_dataset.silver.dataset_id
}

output "bigquery_gold_dataset" {
  value = google_bigquery_dataset.gold.dataset_id
}

output "bronze_external_table_fqn" {
  description = "Fully qualified bronze external table when create_bronze_external_table is true."
  value       = var.create_bronze_external_table ? "${var.project_id}.${google_bigquery_dataset.bronze.dataset_id}.${var.bronze_external_table_id}" : null
}
