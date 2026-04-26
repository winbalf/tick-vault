# Tick Vault — end-to-end testing guide

This document walks you from **zero** through **live exchange data → Kafka (Redpanda) → Flink (bronze consumer) → object storage → (optional) GCS/BigQuery → dbt → Grafana dashboards**, and explains **what each command does after it finishes**, especially when you want **new or refreshed data** at each layer. Optional **Terraform** (`terraform/`) and **Airflow** (`airflow/`) paths are documented in the sections below and in the main README.

For architecture and model details, see the main [`README.md`](README.md). **Reference pairs** (Binance / Kraken / REST presets) live in [§5](#5-changing-symbols-or-forcing-a-producer-restart) under *Reference pairs*.

---

## How the pipeline fits together

```text
Exchanges (Binance WS, Kraken WS, optional REST quotes)
        │
        ▼
  producers (Docker service)  ──►  Redpanda topics (e.g. raw.trades.v1, raw.depth.v1)
        │
        ▼
  Flink bronze job (you submit it)  ──►  MinIO: s3a://tick-vault/bronze/… (Parquet)
        │
        ▼  (optional, for BigQuery + Grafana)
  Sync + bootstrap scripts / gcs-pipeline profile  ──►  GCS + BigQuery external bronze table
        │
        ▼
  dbt  ──►  silver + gold BigQuery tables (what Grafana queries)
```

**Vocabulary**

- **Producer** — Python app in Docker that connects to public APIs/WebSockets and **publishes** validated JSON to Kafka topics. It does **not** “consume” the bronze sink; that name is reserved for **Flink**, which **consumes** Kafka and **writes** Parquet.
- **Consumer (streaming)** — Here, the **Flink bronze job** is the Kafka consumer that reads raw topics and writes bronze Parquet to MinIO (or GCS in production).

---

## What “new data” means at each stage

| You want… | What actually happens | What you do |
|-----------|------------------------|-------------|
| **New live ticks in Kafka** | Binance/Kraken (and optional REST pollers) stream continuously while `producers` is running. | Usually **nothing** — data keeps flowing. To **change symbols/pairs**, edit `.env`, then **recreate** the producers container (see [§5](#5-changing-symbols-or-forcing-a-producer-restart)). |
| **New files in MinIO bronze** | Flink keeps consuming Kafka and rolling/writing Parquet under `bronze/`. | Ensure **Flink job is running** and producers are publishing. Wait for checkpoints and file rolls; list MinIO (see [§7](#7-verify-bronze-parquet-in-minio)). |
| **New objects in GCS / rows visible in BigQuery bronze** | Something must **copy** Parquet from MinIO to `gs://$GCS_BUCKET/bronze/` and refresh the external table metadata. | Re-run **`gcs-pipeline`** or **`./scripts/bronze_to_gcs_and_bq.sh`** (see [§8](#8-optional-path--gcs--bigquery-bronze)). |
| **Updated gold tables for Grafana** | dbt **materializes** models from bronze → silver → gold. | Run **`./scripts/dbt_build.sh`** again (or `dbt run` with a subset) after bronze on GCS is updated ([§9](#9-dbt-silver-and-gold)). |
| **Dashboards showing the latest** | Grafana queries BigQuery; it shows whatever is in gold **for the time range** you selected. | Pick a time range that includes new data; set dashboard **refresh**; re-run dbt if gold is stale. |

---

## Prerequisites

- **Docker** and **Docker Compose** v2 (`docker compose`).
- **This repo** cloned; terminal opened at the repo root (`tick-vault/`).
- **Optional (Grafana + BigQuery path):** Google Cloud project, a **GCS bucket**, BigQuery API enabled, a **service account JSON** with the permissions described in the main README, and that file available as **`keys/gcs.json`** (Compose mounts it into Grafana). Never commit real keys.

---

## 1. Environment file

### Command

```bash
cp .env.example .env
```

### What happens after it runs

- You get a **new `.env`** file (ignored by git) with defaults for brokers, topics, and Binance/Kraken symbols.
- Docker Compose **`env_file: .env`** services (`topic-init`, `producers`, `flink-submit-bronze`, `gcs-pipeline`) will read these variables when they start.

### Optional edits before first `up`

- **`COINGECKO_ENABLED` / `CRYPTOCOMPARE_ENABLED`** — set to `false` if you want fewer topics/API calls.
- For GCP later: set **`GCP_PROJECT_ID`**, **`GCS_BUCKET`**, and run `python3 scripts/sync_grafana_env_from_sa.py` after placing your SA JSON at **`keys/gcs.json`** (updates `.env` with project id, client email, token URI — **not** the private key).

---

## 2. Start the core local stack

### Command

```bash
docker compose up -d --build
```

### Flags

- **`-d`** — **Detached** mode: containers start in the background; your shell returns immediately. Without `-d`, logs stream in the terminal until you press Ctrl+C (which would stop the stack).
- **`--build`** — Rebuilds images **before** starting, so code/Dockerfile changes are picked up. Slower first time; omit on later starts if nothing changed.

### What happens after it runs

Rough startup order (Compose handles dependencies):

| Piece | Role after startup |
|-------|-------------------|
| **redpanda** | Kafka-compatible broker on **`localhost:19092`** (external). |
| **console** | Web UI to browse topics/messages: **`http://localhost:8080`**. |
| **topic-init** | **One-shot** container: runs `scripts/create_topics.py`, creates topics (`raw.trades.v1`, `raw.depth.v1`, etc.), then **exits successfully**. Producers wait for this. |
| **minio** + **minio-init** | S3-compatible storage; **`minio-init`** creates bucket **`tick-vault`** and exits. |
| **flink-jobmanager** / **flink-taskmanager** | Flink cluster REST UI: **`http://localhost:8081`**. **No bronze job is submitted yet** unless you use the **`bronze`** profile (see §6). |
| **producers** | Long-running: connects to exchanges and **writes** to Redpanda continuously. |

**Not started by this command alone:** `grafana` (profile **`grafana`**), `gcs-pipeline` (profile **`gcs`**), `flink-submit-bronze` (profile **`bronze`** — and it is **`restart: "no"`**, so it is meant to be run manually).

### Useful follow-ups

```bash
docker compose ps
```

**After it runs:** prints each service’s **state** (running / exited). You want `redpanda`, `producers`, Flink, MinIO **healthy or running**; `topic-init` and `minio-init` typically **Exit 0**.

```bash
docker compose logs -f producers
```

**After it runs:** streams **producer logs** (Binance connect, Kraken connect, errors). Leave running to verify live ingestion; Ctrl+C stops **only the log follow**, not the container.

---

## 3. Confirm producer → Kafka (“new data” is flowing)

### In the browser

Open **`http://localhost:8080`** (Redpanda Console) → Topics → **`raw.trades.v1`** / **`raw.depth.v1`** → Messages.

### What you should see

- **Increasing offsets** and recent timestamps while **`producers`** is up — that **is** new data arriving from the exchanges.

### CLI alternative (host needs Kafka tools or use Console)

No extra command is required if Console shows traffic.

---

## 4. Optional: bring the stack up including the GCS one-shot (GCP)

Only if you have **`GCP_PROJECT_ID`**, **`GCS_BUCKET`**, and host **`~/.config/gcloud`** authenticated.

### Command

```bash
docker compose --profile gcs up -d --build
```

### What `--profile gcs` does

- **Activates** the **`gcs-pipeline`** service definition. On **`up`**, that service runs **once**: waits (optional `GCS_PIPELINE_WAIT_SECONDS`), mirrors MinIO bronze to GCS if Parquet exists, then runs BigQuery dataset + bronze external table bootstrap (unless skipped by env). See main README for details.

### What happens if bronze is still empty

- Upload may be **skipped** (by design) when there is no Parquet yet; run **`gcs-pipeline`** again after Flink has written files (§6–§8).

---

## 5. Changing symbols or forcing a producer restart

If you edited **`.env`** (e.g. `BINANCE_SYMBOL`, `KRAKEN_PAIR`, poll intervals):

### Command

```bash
docker compose up -d --build producers
```

### What happens after it runs

- Compose **recreates** the **`producers`** container with the **new environment**.
- **New data** will use the new symbols/pairs; Kafka will show messages for the new configuration.

### Reference pairs (Binance, Kraken, REST)

Use **one row at a time** in `.env`: the producers support a **single** Binance stream, one Kraken book, and one REST asset each. Pick a row, set all columns for that row, then recreate the `producers` container (commands above).

| Column | Maps to `.env` |
|--------|----------------|
| Binance symbol | `BINANCE_SYMBOL` |
| Binance trade WebSocket URL | `BINANCE_WS_URL` |
| Kraken pair | `KRAKEN_PAIR` |
| CoinGecko coin id | `COINGECKO_ID` |
| CryptoCompare from-symbol | `CRYPTOCOMPARE_FSYM` |

CoinGecko ids follow [their coin list](https://api.coingecko.com/api/v3/coins/list) (ids are lowercase slugs). CryptoCompare `fsym` is the usual ticker for the **base** asset in a `BASE/USD` quote.

**Ten aligned USDT pairs (Binance spot + Kraken + REST)**

| # | Market (concept) | `BINANCE_SYMBOL` | `BINANCE_WS_URL` | `KRAKEN_PAIR` | `COINGECKO_ID` | `CRYPTOCOMPARE_FSYM` |
|---|------------------|------------------|------------------|---------------|----------------|----------------------|
| 1 | Bitcoin / USDT | `BTCUSDT` | `wss://stream.binance.com:9443/ws/btcusdt@trade` | `XBT/USDT` | `bitcoin` | `BTC` |
| 2 | Ethereum / USDT | `ETHUSDT` | `wss://stream.binance.com:9443/ws/ethusdt@trade` | `ETH/USDT` | `ethereum` | `ETH` |
| 3 | Solana / USDT | `SOLUSDT` | `wss://stream.binance.com:9443/ws/solusdt@trade` | `SOL/USDT` | `solana` | `SOL` |
| 4 | XRP / USDT | `XRPUSDT` | `wss://stream.binance.com:9443/ws/xrpusdt@trade` | `XRP/USDT` | `ripple` | `XRP` |
| 5 | Cardano / USDT | `ADAUSDT` | `wss://stream.binance.com:9443/ws/adausdt@trade` | `ADA/USDT` | `cardano` | `ADA` |
| 6 | Dogecoin / USDT | `DOGEUSDT` | `wss://stream.binance.com:9443/ws/dogeusdt@trade` | `DOGE/USDT` | `dogecoin` | `DOGE` |
| 7 | Avalanche / USDT | `AVAXUSDT` | `wss://stream.binance.com:9443/ws/avaxusdt@trade` | `AVAX/USDT` | `avalanche-2` | `AVAX` |
| 8 | Chainlink / USDT | `LINKUSDT` | `wss://stream.binance.com:9443/ws/linkusdt@trade` | `LINK/USDT` | `chainlink` | `LINK` |
| 9 | Polkadot / USDT | `DOTUSDT` | `wss://stream.binance.com:9443/ws/dotusdt@trade` | `DOT/USDT` | `polkadot` | `DOT` |
| 10 | Litecoin / USDT | `LTCUSDT` | `wss://stream.binance.com:9443/ws/ltcusdt@trade` | `LTC/USDT` | `litecoin` | `LTC` |

`KRAKEN_WS_URL` stays `wss://ws.kraken.com` (default in `.env.example`).

**Notes:** Kraken spot Bitcoin is usually **`XBT/USDT`**, not `BTC/USDT`. The Binance URL path segment before `@trade` must be the **lowercase** `symbol` (no slash). After switching pairs, Grafana variables must match the **`symbol`** and **`exchange`** values present in BigQuery.

---

## 6. Start the Flink bronze consumer (Kafka → MinIO Parquet)

The Flink cluster is already up from §2; you still need to **submit** the PyFlink job **once per cluster** (avoid duplicate jobs writing the same sink).

### Command

```bash
docker compose --profile bronze run --rm flink-submit-bronze
```

### Flags

- **`--profile bronze`** — Includes the **`flink-submit-bronze`** service in this invocation (it is not part of the default `up` set).
- **`run --rm`** — Starts a **one-off** container that submits the job then **exits**; **`--rm`** removes that container afterward.

### What happens after it runs

- Script **`wait_and_submit.sh`** waits for Flink REST, then runs **`flink run -d`** (detached job on the cluster).
- The **bronze** job **consumes** configured Kafka topics and **writes** Hive-partitioned Parquet under **`s3a://tick-vault/bronze/`** in MinIO.
- **Checkpoint** data goes to **`s3a://tick-vault/flink-checkpoints/`** (see `.env` / compose overrides).

### Duplicate submissions

- Running this **again** starts **another** job. Only one should write the same sink; cancel extras in **`http://localhost:8081`**.

---

## 7. Verify bronze Parquet in MinIO

### Command (uses temporary `mc` container on host network)

```bash
docker run --rm --network host --entrypoint /bin/sh minio/mc:RELEASE.2024-08-26T10-49-58Z \
  -c 'mc alias set local http://127.0.0.1:9000 minioadmin minioadmin && mc ls -r local/tick-vault/bronze | head -50'
```

### What happens after it runs

- **`docker run … minio/mc`** — Starts a **short-lived** MinIO Client container.
- **`--network host`** — So **`127.0.0.1:9000`** reaches MinIO published on the host.
- **`mc alias set`** — Configures credentials **`minioadmin` / `minioadmin`** (same as `docker-compose.yml`).
- **`mc ls -r local/tick-vault/bronze`** — Lists **bronze** objects; you should see **`.parquet`** paths growing as Flink writes.

### UI

**`http://localhost:9001`** → bucket **`tick-vault`** → prefix **`bronze/`**.

---

## 8. Optional path — GCS + BigQuery (bronze)

When MinIO has Parquet and you want **BigQuery** (and later Grafana) to see it.

### On the host (typical)

```bash
export GCP_PROJECT_ID="your-project-id"
export GCS_BUCKET="your-bucket-name"
./scripts/bronze_to_gcs_and_bq.sh
```

### What happens after it runs

1. **`sync_bronze_minio_to_gcs.sh`** — Copies/mirrors bronze from MinIO to **`gs://$GCS_BUCKET/bronze/`** (skips empty upload by default; see script/env flags).
2. **`phase2_gcp_bootstrap.sh`** — Ensures BigQuery datasets and **bronze external table** pointing at GCS (unless `SKIP_BQ_BOOTSTRAP=1`).

### From Docker (same scripts, mounted repo + gcloud config)

```bash
docker compose --profile gcs run --rm gcs-pipeline
```

### What happens after it runs

- One container run executes the same **`bronze_to_gcs_and_bq.sh`** flow with **`USE_LOCAL_MC=1`** so MinIO is reached from inside Docker.

### Getting **new** data into BigQuery bronze

- After more Parquet appears in MinIO, **run the same command again** so GCS and the external table see new files.

### Terraform (optional GCP bootstrap)

If you prefer **declarative** infrastructure, use **`terraform/`** to create the bucket, medallion datasets, the bronze external table, and optional IAM for a service account. See **`terraform/README.md`**. After `terraform apply`, put the output bucket name into **`GCS_BUCKET`** in `.env` and continue with sync / dbt as above.

### Airflow (optional scheduled batch lane)

To run **MinIO→GCS → `apply_bronze_external_table.sh` → `dbt_run_pipeline.sh`** on a timer, use the compose file under **`airflow/`** (DAG **`tickvault_minio_gcs_bq_dbt`**). From the repo root:

```bash
export DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"   # macOS: stat -f '%g'
docker compose -f airflow/docker-compose.yml up --build -d
```

Details, auth mounts, and **`TICKVAULT_AIRFLOW_SCHEDULE`**: **`airflow/README.md`**. UI: **http://localhost:8085** (`admin` / `admin` by default).

---

## 9. dbt (silver + gold)

### One-time setup (summary)

- Install: **`pip install -r requirements-dbt.txt`**
- BigQuery datasets / bronze external table: already from §8 or **`./infra/bigquery/apply_datasets.sh`**
- **`dbt/profiles.yml`** from example; **`gcloud auth application-default login`** or SA target.

### Command

```bash
./scripts/dbt_build.sh
```

### What happens after it runs

- Loads **`.env`** if present, runs **`dbt debug`**, then **`dbt build`** (models + tests) so **silver** and **gold** tables match current **bronze** in BigQuery.

### Getting **new** data into gold for Grafana

- After **new bronze** landed in GCS and the external table sees it, **run `./scripts/dbt_build.sh` again** (or `dbt run --select …` for faster iteration).

---

## 10. Grafana dashboards

### Prepare `keys/gcs.json`

- Copy your **service account JSON** to **`keys/gcs.json`** (path expected by `docker-compose.yml`).

### Sync project/email into `.env` (private key stays in JSON only)

```bash
python3 scripts/sync_grafana_env_from_sa.py
```

### What happens after it runs

- Updates **`.env`** with **`GCP_PROJECT_ID`**, **`GCP_CLIENT_EMAIL`**, **`GCP_TOKEN_URI`** for Compose; Grafana still reads the **private key** from the **mounted** `keys/gcs.json`.

### Start Grafana

```bash
docker compose --profile grafana up -d --build grafana
```

### What happens after it runs

- **Grafana** listens on **`http://localhost:3000`**.
- Entrypoint renders BigQuery datasource + dashboards from **`docker/grafana/templates`** and **`docker/grafana/dashboards`**.
- Log in **`admin` / `admin`** (or `GF_ADMIN_PASSWORD`); anonymous Admin is enabled **for local use only** (see `docker/grafana/README.md`).

### In the UI

- Open provisioned dashboards (e.g. **Tick Vault — Live Price & Volume**, **Pipeline Health**).
- Set time range to **Last 24 hours** (or include when your gold data exists).

### Getting dashboards to show **newer** metrics

1. Confirm **gold** tables updated (**§9**).
2. In Grafana, **refresh** and widen **time range** if needed.

---

## 11. One-shot “full path” command cheat sheet

| Goal | Command | After it runs |
|------|---------|----------------|
| Start streaming stack | `docker compose up -d --build` | Redpanda, producers, Flink cluster, MinIO running; topics created. |
| Submit bronze Flink job | `docker compose --profile bronze run --rm flink-submit-bronze` | Flink consumes Kafka → writes Parquet to MinIO. |
| Push bronze to GCS + BQ | `./scripts/bronze_to_gcs_and_bq.sh` or `docker compose --profile gcs run --rm gcs-pipeline` | GCS objects + BigQuery bronze external table (when Parquet exists). |
| Declarative GCP (bucket + BQ) | `cd terraform && terraform apply` | See `terraform/README.md`. |
| Scheduled sync + dbt | `docker compose -f airflow/docker-compose.yml up -d` (after `DOCKER_GID` export) | Airflow DAG `tickvault_minio_gcs_bq_dbt`; see `airflow/README.md`. |
| Refresh marts | `./scripts/dbt_build.sh` | Silver/gold updated in BigQuery. |
| Start Grafana | `docker compose --profile grafana up -d --build grafana` | Dashboards at port **3000**. |
| Stop everything | `docker compose --profile grafana --profile gcs --profile bronze down` | Containers stopped (add **`-v`** to remove volumes — **wipes MinIO data**). |

---

## 12. Troubleshooting (short)

- **`NoBrokersAvailable` in producer logs right after `docker compose up`** — The producer container can start **before** Redpanda accepts Kafka clients, even though Compose waited for the **healthcheck**. **After** Redpanda is healthy, run **`docker compose restart producers`**. **What that does:** stops and starts only the **`producers`** container so `KafkaProducer` reconnects to **`redpanda:9092`**; WebSocket tasks then publish as usual.
- **No messages in Console** — `docker compose logs producers`; check network/firewall; verify Redpanda healthy.
- **No Parquet in MinIO** — Was **`flink-submit-bronze`** run exactly once? Any **RUNNING** job in Flink UI? Any errors in TaskManager logs?
- **Grafana exits / missing key** — Ensure **`keys/gcs.json`** exists on the host at that path.
- **BigQuery / dbt auth errors** — Refresh **`gcloud auth application-default login`** or fix **`GOOGLE_APPLICATION_CREDENTIALS`** / dbt profile.

---

## End-to-end checklist (copy-paste order)

1. `cp .env.example .env` → edit GCP vars if using cloud path.  
2. `docker compose up -d --build` → wait ~30–60s for health.  
3. Open **`http://localhost:8080`** → confirm **`raw.trades.v1`** traffic.  
4. `docker compose --profile bronze run --rm flink-submit-bronze` → confirm Flink job **RUNNING** at **`http://localhost:8081`**.  
5. List MinIO **`bronze/`** (§7).  
6. (GCP) `./scripts/bronze_to_gcs_and_bq.sh` or **`docker compose --profile gcs run --rm gcs-pipeline`**.  
7. `./scripts/dbt_build.sh`.  
8. Place **`keys/gcs.json`**, `python3 scripts/sync_grafana_env_from_sa.py`, then `docker compose --profile grafana up -d --build grafana` → **`http://localhost:3000`**.

You now have a single document that ties **commands → system state → where “new data” comes from** at every layer.
