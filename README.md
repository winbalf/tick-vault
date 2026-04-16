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
- `docker/` - service Dockerfiles
- `scripts/create_topics.py` - topic bootstrap utility
- `src/producers/` - websocket ingestion workers and schemas

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
minio + minio-init --> local S3 bucket ready for next phases (no writes yet)
flink jm/tm ---------> runtime available for future streaming jobs (no jobs yet)
```

### Active in Phase 1

- Live Binance and Kraken websocket consumption
- Producer-side schema validation and normalization
- Publish valid records to `raw.trades.v1` and `raw.depth.v1`
- Route invalid payloads to `dlq.trades`
- Retry + exponential backoff on websocket disconnect

### Prepared for next phases

- Flink services running but no stream processing job submitted yet
- MinIO bucket initialized but no bronze sink writer enabled yet
- Silver/gold transforms (OHLCV, spread, volatility) not started yet

## Source docs

- [Binance WebSocket Streams](https://developers.binance.com/docs/binance-spot-api-docs/web-socket-streams)
- [Kraken API Center](https://docs.kraken.com/websockets/)
- [CryptoCompare API](https://min-api.cryptocompare.com/)
