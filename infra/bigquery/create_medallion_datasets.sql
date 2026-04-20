-- Create empty BigQuery datasets for the medallion layout used by dbt (`dbt/dbt_project.yml` vars).
--
-- BigQuery does not read MinIO. Local bronze Parquet stays under s3a://tick-vault/bronze in Docker.
-- Use this in GCP when you want native BQ tables (dbt silver/gold) and, later, a bronze *external*
-- table only after Parquet lives on gs://… (see `bronze_external_tables.sql`).
--
-- Replace placeholders, then run in the BigQuery console or:
--   bq query --use_legacy_sql=false < infra/bigquery/create_medallion_datasets.sql
-- (after substituting PROJECT and LOCATION in this file, or use `apply_datasets.sh`.)

CREATE SCHEMA IF NOT EXISTS `PROJECT.tickvault_bronze`
OPTIONS (location = 'LOCATION');

CREATE SCHEMA IF NOT EXISTS `PROJECT.tickvault_silver`
OPTIONS (location = 'LOCATION');

CREATE SCHEMA IF NOT EXISTS `PROJECT.tickvault_gold`
OPTIONS (location = 'LOCATION');
