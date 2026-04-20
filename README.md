# tick-vault

Crypto market microstructure pipeline that ingests real-time ticks/order book depth from exchange WebSockets, lands all raw events in bronze-compatible streams, and prepares the stack for silver/gold analytics (OHLCV, spread, volatility) and Grafana dashboards.

## Phase 1 scope

- Docker Compose stack for Redpanda, Flink, and MinIO
- Python producers for:
  - Binance trade stream
  - Kraken order book stream
  - CoinGecko and CryptoCompare REST quotes (optional; enabled by default)
- Pydantic schema contracts at producer ingestion
- DLQ routing on malformed payloads
- Redpanda topic bootstrap:
  - `raw.trades.v1`
  - `raw.depth.v1`
  - `raw.coingecko.v1`
  - `raw.cryptocompare.v1`
  - `dlq.trades`

## Quickstart

1. Copy env file:
   - `cp .env.example .env`
2. Start stack:
   - `docker compose up --build`
   - **Optional (GCP):** after `gcloud auth application-default login` (or service-account auth in `~/.config/gcloud`) and `GCP_PROJECT_ID` / `GCS_BUCKET` in `.env`, bring the stack up **with** the GCS profile so a one-shot job syncs bronze when Parquet exists and registers BigQuery: `docker compose --profile gcs up --build -d`. Re-run the job any time with `docker compose --profile gcs run --rm gcs-pipeline`. See **Phase 2 — GCP path**.
3. Verify services:
   - Redpanda Console: `http://localhost:8080`
   - Flink UI: `http://localhost:8081`
   - MinIO Console: `http://localhost:9001` (minioadmin/minioadmin)

## Project structure

- `docker-compose.yml` - local streaming stack orchestration
- `docker/` - producer and Flink Dockerfiles
- `docker/flink/` - Flink image (Kafka + Parquet + S3/GS plugins) and bronze job submit script
- `scripts/create_topics.py` - topic bootstrap utility
- `scripts/validate_bronze_offsets.py` - compare Kafka high-water sums to Parquet/BigQuery counts
- `scripts/sync_bronze_minio_to_gcs.sh` - mirror MinIO bronze Parquet to GCS for BigQuery
- `scripts/bronze_to_gcs_and_bq.sh` - sync (skips empty upload by default) + `phase2_gcp_bootstrap.sh`
- `docker/gcs-pipeline/` - image used by Compose **profile `gcs`** (`gcs-pipeline` service) for the same flow inside Docker
- `scripts/test_gcs_bronze_connection.sh` - verify `GCP_PROJECT_ID` / `GCS_BUCKET` from `.env` and list `gs://…/bronze/`
- `scripts/phase2_gcp_bootstrap.sh` / `scripts/phase2_upload_and_bootstrap.sh` - BigQuery datasets + bronze external table (optional upload + bootstrap)
- `scripts/dbt_build.sh` - `dbt debug` + `dbt build` with optional `.env` and local `dbt/profiles.yml`
- `.github/workflows/dbt.yml` - CI: `dbt parse` and docs with empty catalog
- `docker/grafana/` - Grafana provisioning (BigQuery datasource template + sample dashboard)
- `infra/gcs/` - GCS lifecycle (90-day bronze prefix) helper
- `infra/bigquery/` - medallion dataset bootstrap (`apply_datasets.sh`, `create_medallion_datasets.sql`) and external table DDL for GCS-backed bronze
- `dbt/` - BigQuery medallion transforms (silver staging, gold mart) and docs
- `src/producers/` - websocket ingestion workers and schemas
- `src/flink_jobs/` - PyFlink streaming jobs

## Data contracts

- `TradeEvent`:
  - venue, symbol, trade_id, event_ts_ms, price, quantity, is_buyer_maker, ingest_ts
- `OrderBookEvent`:
  - venue, symbol, update_id, event_ts_ms, bids, asks, ingest_ts
- `RestQuoteEvent` (CoinGecko / CryptoCompare):
  - venue (`coingecko` or `cryptocompare`), symbol, quote_id, event_ts_ms, price_usd, ingest_ts, raw_event
- `DlqEvent`:
  - source, reason, raw_payload, ingest_ts

All payloads are validated via Pydantic before publishing to the primary raw topics.

## Phase 1 message flow

```text
Binance WS (trade stream) ----\
                                > producers service --> Pydantic validation --> raw.trades.v1 (Redpanda)
Kraken WS (order book) -------/                                |
CoinGecko REST -------------+--> raw.coingecko.v1               |
CryptoCompare REST ---------+--> raw.cryptocompare.v1           |
                                                               +--> dlq.trades (malformed events)

topic-init -----------> creates required topics before producers start
console -------------> inspect topics/messages at localhost:8080
minio + minio-init --> bucket `tick-vault` (S3A sink target for local bronze)
flink jm/tm ---------> PyFlink bronze job (submit via `flink-submit-bronze` service)
```

### Active in Phase 1

- Live Binance and Kraken websocket consumption
- Periodic CoinGecko and CryptoCompare USD quotes (HTTP), when enabled in `.env`
- Producer-side schema validation and normalization
- Publish valid records to `raw.trades.v1`, `raw.depth.v1`, `raw.coingecko.v1`, and `raw.cryptocompare.v1`
- Route invalid payloads to `dlq.trades`
- Retry + exponential backoff on websocket disconnect

### Prepared for next phases

- Silver/gold transforms (OHLCV, spread, volatility) and Grafana marts: see Phase 3

## Phase 2 — Bronze (Redpanda → Parquet → BigQuery-ready)

**Local vs GCP:** MinIO is your **S3-compatible object store** inside Docker (`s3a://tick-vault/...`). **BigQuery cannot read MinIO** (no `s3a://` or private MinIO endpoint for native external tables). For local development, bronze data lives only in MinIO until you copy it to **GCS** or load it into BigQuery some other way. Google Cloud here is mainly **BigQuery datasets + dbt** for silver/gold; a **GCS bucket is only required** if you want BigQuery **external** tables over Parquet (`gs://…`), which matches production Flink.

**Local:** Flink reads `raw.trades.v1` and `raw.depth.v1`, writes **Hive-style** Parquet under `s3a://tick-vault/bronze/` (MinIO), partitioned by **`dt` / `symbol` / `exchange`** (UTC calendar date from `event_ts_ms`, path-safe symbol, venue as exchange). Checkpoints land under `s3a://tick-vault/flink-checkpoints/`.

### Verify MinIO bronze data

With the stack running (`docker compose up -d` including MinIO), list objects under the `tick-vault` bucket:

```bash
docker run --rm --network host --entrypoint /bin/sh minio/mc:RELEASE.2024-08-26T10-49-58Z \
  -c 'mc alias set local http://127.0.0.1:9000 minioadmin minioadmin && mc ls -r local/tick-vault/bronze | head -50'
```

Or open **MinIO Console** at `http://localhost:9001` (same credentials as in `docker-compose.yml`), bucket **tick-vault**, prefix **bronze/**.

**Submit the job** (JobManager and TaskManagers must already be up):

- `docker compose up -d minio minio-init redpanda topic-init flink-jobmanager flink-taskmanager`
- `docker compose --profile bronze run --rm flink-submit-bronze` (detached `flink run -d`; job keeps running on the cluster; profile avoids auto-submit on every `docker compose up`)

**Production:** set `BRONZE_SINK_BASE` / `CHECKPOINT_DIR` to `gs://...` on Flink and ensure the cluster has GCS credentials plus `flink-gs-fs-hadoop` on the classpath (already copied into this repo’s Flink image from `/opt/flink/opt`).

### GCP path from local MinIO (automated)

BigQuery bronze in this repo is an **external table** over **`gs://$GCS_BUCKET/bronze/**`**, so GCS is part of the path whenever you use that pattern (local MinIO is still the Flink sink until you change `BRONZE_SINK_BASE`).

**A) Compose profile `gcs` (recommended when developing with Docker):**

1. Authenticate on the **host** so credentials live under `~/.config/gcloud` (for example `gcloud auth application-default login` and/or `gcloud auth login`). The `gcs-pipeline` container bind-mounts that directory as `/root/.config/gcloud`.
2. Set `GCP_PROJECT_ID` and `GCS_BUCKET` in `.env` (bucket name only, no `gs://`).
3. Optional: `GCS_PIPELINE_WAIT_SECONDS=120` in `.env` to wait before syncing (gives Flink/producers time after `compose up`).
4. Start the stack **with** the profile: `docker compose --profile gcs up --build -d`. The **`gcs-pipeline`** service runs once: mirror from MinIO, **upload to GCS only if at least one Parquet file exists** (otherwise it skips upload but still continues), then creates BigQuery datasets and the bronze external table.
5. Any time you need to push fresh bronze to GCS and refresh metadata: `docker compose --profile gcs run --rm gcs-pipeline`.

**B) Host scripts (same behavior, uses Docker only for `mc` unless `USE_LOCAL_MC=1`):**

1. Authenticate for GCS and BigQuery (`gcloud auth application-default login` or a service account with Storage write + BigQuery jobs/data admin as needed).
2. Put `GCP_PROJECT_ID` and `GCS_BUCKET` in `.env` (bucket name only, no `gs://`; avoid trailing spaces) or export them in your shell.
3. **Check GCS:** `./scripts/test_gcs_bronze_connection.sh` — reads `.env`, describes the bucket, and lists objects under `gs://$GCS_BUCKET/bronze/`.
4. **Sync + BigQuery in one step:** `./scripts/bronze_to_gcs_and_bq.sh` (skips GCS upload when the MinIO mirror has no Parquet unless you set `SKIP_GCS_UPLOAD_IF_NO_PARQUET=0`). For a forced rsync even when empty, use `./scripts/phase2_upload_and_bootstrap.sh`.
5. **Upload only:** `./scripts/sync_bronze_minio_to_gcs.sh` (optional: `MINIO_ENDPOINT`, `DOCKER_MC_NETWORK`, keys; Docker `mc` + `gcloud storage rsync` or `gsutil`).
6. **Datasets + external table only:** `./scripts/phase2_gcp_bootstrap.sh`.

Manual alternative: edit and run `infra/bigquery/bronze_external_tables.sql` in the console or `bq query`.

### Bronze Parquet columns (queryable + pruning keys)

| Column | Type (logical) | Notes |
| --- | --- | --- |
| `stream_kind` | string | `trades`, `depth`, `coingecko`, or `cryptocompare` |
| `payload` | string | Full JSON record from Redpanda (raw tick as published) |
| `exchange` | string | Same as producer `venue` (e.g. `binance`, `kraken`) |
| `symbol` | string | Path-safe symbol for partitions (`/` → `-`, `:` → `_`); full symbol remains inside `payload` |
| `event_ts_ms` | bigint | From payload when present |
| `ingest_ts` | string | ISO timestamp string from payload |
| `kafka_topic` | string | Kafka metadata |
| `kafka_partition` | int | Kafka metadata |
| `kafka_offset` | bigint | Kafka metadata (use for offset reconciliation) |
| `kafka_ts` | timestamp(3) | Kafka record timestamp |
| `dt` | string | `yyyy-MM-dd` partition key (UTC) |

**GCP**

- Lifecycle (delete objects under `bronze/` older than 90 days): `./infra/gcs/apply_lifecycle_bronze.sh gs://YOUR_BUCKET`
- BigQuery external table: use `./infra/bigquery/apply_bronze_external_table.sh` after upload, or edit placeholders in `infra/bigquery/bronze_external_tables.sql` and run manually.

**Validation**

- `pip install -r requirements-bronze-tools.txt`
- `python scripts/validate_bronze_offsets.py --kafka-bootstrap localhost:19092 --parquet-s3-prefix s3://tick-vault/bronze` (optional `--bigquery-table project.dataset.table`)

Offsets are approximate: Kafka retention/compaction, Flink at-least-once duplicates, and lag while the job catches up can all skew counts.

## Phase 3 — Silver and gold (dbt on BigQuery)

Medallion models read the bronze external table (`tickvault_bronze`), materialize silver in `tickvault_silver`, and the Grafana-ready mart in `tickvault_gold`. Override dataset names or project with dbt `--vars` (see `dbt/dbt_project.yml`).

**Prerequisites**

- BigQuery datasets exist (for example `tickvault_bronze`, `tickvault_silver`, `tickvault_gold`) and your principal can create tables in the silver and gold datasets. Bootstrap empty datasets with `./infra/bigquery/apply_datasets.sh` (see **Setup**).
- For `dbt run` as shipped, the **bronze** layer must exist as a **BigQuery** table (the `bronze.tickvault_bronze` source). With MinIO-only local bronze, use **Phase 2** upload + `apply_bronze_external_table.sh` (or the SQL file) after Parquet is on **GCS**, or maintain an equivalent native table yourself. The same principal then needs **Storage Object Viewer** on that GCS prefix if you use an external table.

**Setup**

- `pip install -r requirements-dbt.txt`
- `export GCP_PROJECT_ID=...` (and auth). Create datasets: `./infra/bigquery/apply_datasets.sh` (optional `BQ_LOCATION`, defaults to `us-central1`). Or run `infra/bigquery/create_medallion_datasets.sql` in the console after replacing `PROJECT` and `LOCATION`.
- Copy `dbt/profiles.yml.example` to `~/.dbt/profiles.yml`, or copy it to `dbt/profiles.yml` and run dbt with `DBT_PROFILES_DIR` pointing at the `dbt/` directory. Use `dev_oauth` (`gcloud auth application-default login`) or set `target: dev_sa` and export `GCP_PROJECT_ID` and `GOOGLE_APPLICATION_CREDENTIALS` (absolute path to the SA JSON) before `dbt` (`.env` is not read automatically unless you source it).
- Export `GCP_PROJECT_ID` if you prefer not to pass `gcp_project_id` via `--vars`.

**Run**

- From repo root: `./scripts/dbt_build.sh` (sources `.env` if present; uses `dbt/profiles.yml` when `DBT_PROFILES_DIR` is unset and that file exists). Or: `cd dbt && dbt run` then `dbt test`.
- Models built: `stg_trades`, `stg_depth`, `int_ohlcv_1m`, `int_depth_1m`, and `fct_market_metrics` (partitioned by `metric_date`, clustered by `symbol` and `exchange`).
- Documentation: `cd dbt && dbt docs generate` (with credentials, BigQuery fills `catalog.json`). Without warehouse access: `dbt parse && dbt docs generate --no-compile --empty-catalog`. Then `dbt docs serve`.

Gold mart columns include `metric_ts`, `metric_date` (partition), `open`, `high`, `low`, `close`, `volume`, `vwap`, `spread_bps` (from `int_depth_1m` when the venue publishes book snapshots), `volatility` (15-minute rolling stdev of log close returns), `volatility_60m`, and supporting mid price fields for spread QA.

### Grafana (local)

- `docker compose --profile grafana up -d grafana` then open `http://localhost:3000` (default admin password `GF_ADMIN_PASSWORD` or `admin`; anonymous access is enabled with **Admin** org role for local convenience only).
- The container installs `grafana-bigquery-datasource` and sets the datasource **default project** from `GCP_PROJECT_ID`. You still complete **BigQuery JWT** (or your org’s auth method) under Connections → Data sources → BigQuery. See `docker/grafana/README.md`.
- Dashboard **Tick Vault — market metrics** is file-provisioned; set the **GCP project** and **Gold dataset** variables to match your project (defaults are placeholders).

### End-to-end checklist (local stack → BigQuery → dbt → Grafana)

1. `docker compose up -d` (include producers, Flink, MinIO; submit bronze with `--profile bronze` when ready).
2. Confirm Parquet under MinIO (`bronze/` prefix).
3. `export GCP_PROJECT_ID=... GCS_BUCKET=...` → `./scripts/phase2_upload_and_bootstrap.sh`.
4. Copy `dbt/profiles.yml.example` to `dbt/profiles.yml` (or `~/.dbt/profiles.yml`), set project and auth → `./scripts/dbt_build.sh`.
5. `docker compose --profile grafana up -d grafana` → add BigQuery JWT → open the Tick Vault dashboard.

## Source docs

- [Binance WebSocket Streams](https://developers.binance.com/docs/binance-spot-api-docs/web-socket-streams)
- [Kraken API Center](https://docs.kraken.com/websockets/)
- [CryptoCompare API](https://min-api.cryptocompare.com/)

CoinGecko and CryptoCompare are wired into `raw.coingecko.v1` / `raw.cryptocompare.v1` and the Flink bronze union (`stream_kind` = `coingecko` / `cryptocompare`). dbt silver/gold models still filter trades and depth only; extend dbt if you want REST quotes in marts.
