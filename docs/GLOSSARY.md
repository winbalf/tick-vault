# Tick Vault — glossary

Short definitions of **terms and abbreviations** used across this repo. For how pieces connect, see the root [`README.md`](../README.md) (Architecture) and [`TESTING_README.md`](../TESTING_README.md) (runbooks).

---

## Abbreviations

| Abbreviation | Meaning |
| --- | --- |
| **ADC** | Application Default Credentials — Google client libraries use this to find credentials (often from `gcloud auth application-default login`). |
| **API** | Application Programming Interface — here, mostly HTTP/REST (CoinGecko, CryptoCompare) or exchange WebSocket APIs. |
| **BQ** | BigQuery — Google’s managed data warehouse; silver/gold tables and optional bronze **external** tables live here. |
| **bps** | Basis points — 1 bp = 0.01%. Used for **spread** and price deviation in dashboards (e.g. `spread_bps`). |
| **DAG** | Directed Acyclic Graph — in **Airflow**, a scheduled workflow definition (this repo’s DAG syncs bronze → GCS → BigQuery metadata → dbt). |
| **DLQ** | Dead Letter Queue — a dedicated Kafka topic (`dlq.trades`) for messages that failed validation or could not be parsed as expected. |
| **dbt** | **data build tool** — SQL-centric transformation layer; models in `dbt/` build silver/gold from bronze. |
| **GCP** | Google Cloud Platform — umbrella for GCS, BigQuery, IAM, etc. |
| **GCS** | Google Cloud Storage — object store; bronze Parquet is mirrored to `gs://…/bronze/` so BigQuery can read it as an external table. |
| **HFT** | High-frequency trading — ultra-low-latency execution; **not** what this project optimizes for. |
| **HTTP / REST** | Request/response style APIs — used for optional quote polling (CoinGecko, CryptoCompare) alongside WebSockets. |
| **IAM** | Identity and Access Management — who can read/write buckets, run BigQuery jobs, etc. |
| **JWT** | JSON Web Token — one way Grafana authenticates to BigQuery in local setups (see `docker/grafana/README.md`). |
| **OHLCV** | Open, High, Low, Close, Volume — standard candlestick aggregates over a time bucket (e.g. 1 minute). |
| **PyFlink** | Python API for **Apache Flink** — the bronze job in `src/flink_jobs/` runs on the Flink cluster. |
| **REST** | Representational State Transfer — here, “REST quotes” means periodic HTTP pulls for spot USD prices vs streaming trades/books. |
| **SA** | Service Account — GCP robot identity, often a JSON key file for CI or Grafana mounts (`keys/gcs.json`). |
| **SLA** | Service Level Agreement — in code/docs, often “freshness SLA”: how stale data may be before dbt warns or fails (see `dbt` source freshness). |
| **S3A** | Hadoop-style URI scheme (`s3a://bucket/...`) Flink uses to write to **S3-compatible** storage (MinIO locally). |
| **UI** | User Interface — e.g. Redpanda Console, Flink dashboard, MinIO console, Grafana. |
| **VWAP** | Volume-Weighted Average Price — average trade price weighted by size over a window. |
| **WS** | WebSocket — persistent bidirectional connection used by Binance/Kraken streams. |

---

## Architecture & data engineering

**Apache Flink**  
Distributed stream processor. In Tick Vault, a **PyFlink** job consumes Kafka topics and writes **bronze** Parquet with checkpoints for fault tolerance.

**At-least-once**  
Delivery semantics where the same event may be processed more than once after failures; offset reconciliation and counts can differ slightly (see `validate_bronze_offsets.py` notes in the README).

**BigQuery external table**  
A table definition in BigQuery that reads files (here, **Parquet**) from **GCS** without loading them into native BigQuery storage first. BigQuery cannot read MinIO directly; sync to GCS first.

**Bronze / silver / gold (medallion)**  
Layered data design: **bronze** = raw or minimally typed events as landed; **silver** = cleaned, conformed staging (`stg_*`, `int_*`); **gold** = business-ready marts (`fct_*`) for dashboards.

**Checkpoint (Flink)**  
Periodic snapshot of operator state to durable storage (`flink-checkpoints/` in MinIO by default) so the job can recover after failure without re-reading all of history from scratch.

**Compose profile**  
Docker Compose feature (`--profile bronze`, `gcs`, `grafana`) that activates optional services so you do not start heavy components unless you mean to.

**Consumer (in this repo)**  
The **Flink bronze job** is the Kafka **consumer** that reads `raw.*` topics and writes Parquet. Do not confuse with “consumer” meaning “dashboard user.”

**Dead letter queue (topic)**  
Kafka topic `dlq.trades` for rejected payloads; surfaced in gold as **`dead_letter_count`** for monitoring.

**dbt model prefixes**  
- `stg_` — staging (typed, one-source views/tables).  
- `int_` — intermediate logic (aggregations, joins).  
- `fct_` — fact / mart table for analytics (here, `fct_market_metrics`).

**External table**  
See **BigQuery external table**.

**Hive-style partitioning**  
Directory layout like `dt=YYYY-MM-DD/symbol=…/exchange=…` so query engines can **prune** files by filter; bronze uses `dt`, `symbol`, `exchange`.

**Kafka / Redpanda**  
**Kafka** is the de facto API for log-style event streaming. **Redpanda** is a Kafka-compatible broker used locally instead of running full Apache Kafka.

**Mart**  
A curated, denormalized or wide **fact** table (or star schema) optimized for reporting — here, **`fct_market_metrics`** for Grafana.

**Microstructure (market)**  
Short-horizon price formation: trades, quotes, spreads, liquidity — as opposed to long-only “macro” narratives.

**MinIO**  
S3-compatible object store in Docker; local stand-in for cloud object storage. Flink sinks bronze to `s3a://tick-vault/...`.

**Parquet**  
Columnar file format; efficient for analytics and BigQuery external tables.

**Producer**  
Python service in Docker that connects to exchanges/APIs, validates with **Pydantic**, and **publishes** JSON to Kafka topics (`raw.trades.v1`, etc.).

**Pydantic**  
Python library for schema validation; invalid events go to the DLQ instead of corrupting raw topics.

**Topic**  
Named Kafka log (e.g. `raw.trades.v1`) that producers append to and Flink consumes.

**Terraform / IaC**  
**Infrastructure as code** — `terraform/` declares GCS buckets, BigQuery datasets, and optional IAM instead of clicking in the console.

---

## Market & metrics (as used in this project)

**Bid–ask spread**  
Difference between best ask and best bid (often shown in **bps** in `fct_market_metrics` when depth data exists).

**Depth / order book**  
Levels of bids and asks at a venue; Kraken stream feeds **`OrderBookEvent`** and downstream spread logic.

**Mid price**  
Average of best bid and best ask; used with VWAP/spread for QA panels.

**OHLCV**  
Per time bucket: first trade price (**open**), extremes (**high**/**low**), last (**close**), total **volume**.

**Tick / trade**  
Individual trade print (price, size, aggressor side, etc.) from venues like Binance.

**Venue vs exchange (fields)**  
In schemas, **`venue`** is the source name (e.g. `binance`); bronze also stores **`exchange`** aligned with partitioning — in practice they match the same concept for this pipeline.

**Volatility (here)**  
Rolling standard deviation of log returns of **close** over a window (e.g. 15m / 60m), not implied vol from options.

**VWAP**  
Volume-weighted average price over the bucket; compares to mid for execution-quality style views.

---

## Google Cloud & security (local + cloud path)

**Application Default Credentials**  
See **ADC**.

**GCS bucket**  
Named container for objects; Tick Vault expects bronze under the `bronze/` prefix for BigQuery hive discovery.

**Service account**  
See **SA**.

**Storage Object Viewer**  
IAM role often needed to query BigQuery external tables over GCS prefixes.

---

## Project-specific names

**`BRONZE_SINK_BASE` / `CHECKPOINT_DIR`**  
Flink configuration for where Parquet and checkpoints are written (MinIO `s3a://` locally, or `gs://` in production-style setups).

**`fct_market_metrics`**  
Gold fact table Grafana queries: OHLCV, spread, volatility, DLQ counts, anomaly flags, etc.

**`gcs-pipeline`**  
Docker Compose service (profile **`gcs`**) that mirrors MinIO bronze to GCS and runs BigQuery bootstrap scripts.

**`raw.*.v1` topics**  
Versioned raw ingest topics (`raw.trades.v1`, `raw.depth.v1`, optional REST topics).

**`stream_kind`**  
Column in bronze Parquet indicating source stream type: `trades`, `depth`, `coingecko`, `cryptocompare`.

**`tickvault_bronze` / `tickvault_silver` / `tickvault_gold`**  
Default BigQuery dataset names for medallion layers (override via dbt `--vars` / project settings).

**`SKIP_GCS_UPLOAD_IF_NO_PARQUET`**  
Environment flag: when set to `0`, forces sync attempts even if no Parquet was detected (see root [`README.md`](../README.md) Phase 2 and [`TESTING_README.md`](../TESTING_README.md) §8).

---

## Related docs

- Root [`README.md`](../README.md) — phases, contracts, architecture diagram; Grafana in the stack: [Phase 5](../README.md#phase-5--grafana-dashboards--reporting).  
- [`TESTING_README.md`](../TESTING_README.md) — commands and troubleshooting ([Grafana §10](../TESTING_README.md#10-grafana-dashboards)).  
- [`docker/grafana/README.md`](../docker/grafana/README.md) — Grafana JWT, `.env`, dashboards, and alerting (cross-linked from the root README **Glossary** section and Phase 5).
