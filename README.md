# tick-vault

Crypto market microstructure pipeline that ingests real-time ticks/order book depth from exchange WebSockets, lands all raw events in bronze-compatible streams, and prepares the stack for silver/gold analytics (OHLCV, spread, volatility) and Grafana dashboards.

## Phase 1 scope

- Docker Compose stack for Redpanda, Flink, and MinIO
- Python producers for:
  - Binance trade stream
  - Kraken order book stream
- Pydantic schema contracts at producer ingestion
- DLQ routing on malformed payloads
- Redpanda topic bootstrap:
  - `raw.trades.v1`
  - `raw.depth.v1`
  - `dlq.trades`

## Quickstart

1. Copy env file:
   - `cp .env.example .env`
2. Start stack:
   - `docker compose up --build`
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
- `infra/gcs/` - GCS lifecycle (90-day bronze prefix) helper
- `infra/bigquery/` - external table DDL over Hive-partitioned bronze Parquet
- `src/producers/` - websocket ingestion workers and schemas
- `src/flink_jobs/` - PyFlink streaming jobs

## Data contracts

- `TradeEvent`:
  - venue, symbol, trade_id, event_ts_ms, price, quantity, is_buyer_maker, ingest_ts
- `OrderBookEvent`:
  - venue, symbol, update_id, event_ts_ms, bids, asks, ingest_ts
- `DlqEvent`:
  - source, reason, raw_payload, ingest_ts

All payloads are validated via Pydantic before publishing to the primary raw topics.

## Phase 1 message flow

```text
Binance WS (trade stream) ----\
                                > producers service --> Pydantic validation --> raw.trades.v1 (Redpanda)
Kraken WS (order book) -------/                                |
                                                               +--> dlq.trades (malformed events)

topic-init -----------> creates required topics before producers start
console -------------> inspect topics/messages at localhost:8080
minio + minio-init --> bucket `tick-vault` (S3A sink target for local bronze)
flink jm/tm ---------> PyFlink bronze job (submit via `flink-submit-bronze` service)
```

### Active in Phase 1

- Live Binance and Kraken websocket consumption
- Producer-side schema validation and normalization
- Publish valid records to `raw.trades.v1` and `raw.depth.v1`
- Route invalid payloads to `dlq.trades`
- Retry + exponential backoff on websocket disconnect

### Prepared for next phases

- Silver/gold transforms (OHLCV, spread, volatility) and Grafana marts not started yet

## Phase 2 — Bronze (Redpanda → Parquet → BigQuery-ready)

**Local:** Flink reads `raw.trades.v1` and `raw.depth.v1`, writes **Hive-style** Parquet under `s3a://tick-vault/bronze/` (MinIO), partitioned by **`dt` / `symbol` / `exchange`** (UTC calendar date from `event_ts_ms`, path-safe symbol, venue as exchange). Checkpoints land under `s3a://tick-vault/flink-checkpoints/`.

**Submit the job** (JobManager and TaskManagers must already be up):

- `docker compose up -d minio minio-init redpanda topic-init flink-jobmanager flink-taskmanager`
- `docker compose --profile bronze run --rm flink-submit-bronze` (detached `flink run -d`; job keeps running on the cluster; profile avoids auto-submit on every `docker compose up`)

**Production:** set `BRONZE_SINK_BASE` / `CHECKPOINT_DIR` to `gs://...` on Flink and ensure the cluster has GCS credentials plus `flink-gs-fs-hadoop` on the classpath (already copied into this repo’s Flink image from `/opt/flink/opt`).

### Bronze Parquet columns (queryable + pruning keys)

| Column | Type (logical) | Notes |
| --- | --- | --- |
| `stream_kind` | string | `trades` or `depth` |
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
- BigQuery external table: edit placeholders in `infra/bigquery/bronze_external_tables.sql`, then create the table in the console or `bq query`.

**Validation**

- `pip install -r requirements-bronze-tools.txt`
- `python scripts/validate_bronze_offsets.py --kafka-bootstrap localhost:19092 --parquet-s3-prefix s3://tick-vault/bronze` (optional `--bigquery-table project.dataset.table`)

Offsets are approximate: Kafka retention/compaction, Flink at-least-once duplicates, and lag while the job catches up can all skew counts.

## Source docs

- [Binance WebSocket Streams](https://developers.binance.com/docs/binance-spot-api-docs/web-socket-streams)
- [Kraken API Center](https://docs.kraken.com/websockets/)
- [CryptoCompare API](https://min-api.cryptocompare.com/)
