variable "project_id" {
  description = "GCP project id (same as dbt / gcloud)."
  type        = string
}

variable "primary_region" {
  description = "Default region for regional resources (GCS bucket location uses bucket_location)."
  type        = string
  default     = "US"
}

variable "bucket_name" {
  description = "Globally unique GCS bucket name for bronze and pipeline artifacts."
  type        = string
}

variable "bucket_location" {
  description = "GCS bucket location (e.g. US, EU, or a single region like us-central1)."
  type        = string
  default     = "US"
}

variable "bucket_force_destroy" {
  description = "If true, deleting the bucket via Terraform removes all objects (dev only)."
  type        = bool
  default     = false
}

variable "bq_location" {
  description = "BigQuery dataset location (must align with dbt profiles.yml, often US or EU)."
  type        = string
  default     = "US"
}

variable "bronze_dataset_id" {
  type    = string
  default = "tickvault_bronze"
}

variable "silver_dataset_id" {
  type    = string
  default = "tickvault_silver"
}

variable "gold_dataset_id" {
  type    = string
  default = "tickvault_gold"
}

variable "bronze_external_table_id" {
  type    = string
  default = "tickvault_bronze"
}

variable "create_bronze_external_table" {
  description = "Create the Hive-partitioned bronze external table over gs://bucket/bronze/*. Disable if you manage DDL only via shell/dbt."
  type        = bool
  default     = true
}

variable "pipeline_service_account_email" {
  description = "Optional service account (e.g. dbt or Airflow) to grant GCS + BigQuery dataset roles. Leave empty to skip IAM bindings."
  type        = string
  default     = ""
}

variable "enable_project_apis" {
  description = "If true, enable storage.googleapis.com and bigquery.googleapis.com on the project."
  type        = bool
  default     = false
}
