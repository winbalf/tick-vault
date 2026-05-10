# Tick Vault Grafana Dashboards - Full Report Meaning Guide

This document summarizes every current dashboard in `docker/grafana/dashboards/*.json`, what each report shows, and its real operational meaning.

Dashboards filter on **`instrument_id`** (canonical `BASE-QUOTE` from dbt, e.g. `BTC-USDT`, `BTC-USD`). Venue partition **`symbol`** (e.g. `BTCUSDT`, `XBT-USDT`) still appears in some tables for drill-down.

## `tickvault-debug.json` (Tick Vault - Debug BigQuery)

### BigQuery connection
- **What it shows:** Always returns `1` when Grafana can execute a simple query.
- **Real meaning:** Data source/auth/connectivity heartbeat. If red, root cause is likely infra/permissions rather than market logic.

### fct_market_metrics exists
- **What it shows:** `1` if `${gold_dataset}.fct_market_metrics` exists.
- **Real meaning:** Schema deployment guardrail. If `0`, pipeline may be running but this dashboard has no target table.

### Rows in last 2d
- **What it shows:** 2-day row count for selected `exchange` and `instrument_id`.
- **Real meaning:** Continuity and throughput sanity check. Drops often indicate outages, filter mismatch, or upstream lag.

### Freshness lag (seconds)
- **What it shows:** `now - max(metric_ts)` in seconds.
- **Real meaning:** End-to-end staleness KPI (most important on-call metric).

### Latest metric_ts (epoch)
- **What it shows:** Latest event timestamp as epoch seconds.
- **Real meaning:** Forensic timestamp for exact cross-system comparison.

### Total rows in table
- **What it shows:** Full historical row count under current filters.
- **Real meaning:** Growth/retention sanity check; useful for truncation/backfill anomalies, weak for real-time alerting.

### Rows by exchange / instrument / venue symbol (2d)
- **What it shows:** Per `(exchange, instrument_id, symbol)` count and latest timestamp over 2 days.
- **Real meaning:** Coverage map to detect silent partial failures (one venue stale while others are healthy), with both canonical and raw venue symbols.

### Latest 100 rows
- **What it shows:** Last records with `instrument_id`, `symbol`, `base_asset`, `quote_asset`, `close`, `volume`, `spread_bps`, `volatility`, `dead_letter_count`.
- **Real meaning:** Ground-truth sample for spot-checking value plausibility and troubleshooting anomalies.

## `tickvault-overview.json` (Tick Vault - Live Price & Volume)

### Live candlestick
- **What it shows:** OHLC candles (`open/high/low/close`) over last 2 days.
- **Real meaning:** Market structure view. Useful for trend/reversal context and validating that price formation is coherent.

### Live traded volume by instrument
- **What it shows:** Time-series bars of `volume` per `exchange:instrument_id`.
- **Real meaning:** Liquidity/activity monitor. Spikes signal participation bursts; flatlines can indicate feed or venue interruptions.

### Cross-exchange close price (same instrument)
- **What it shows:** `close` by exchange for one `instrument_id`.
- **Real meaning:** Venue consistency panel. Persistent divergence can imply latency asymmetry, microstructure differences, or bad ticks.

## `tickvault-spread-vwap.json` (Tick Vault - Spread & VWAP)

### Bid-ask spread over time
- **What it shows:** `spread_bps` time series by `exchange:instrument_id`.
- **Real meaning:** Tradability/liquidity cost signal. Wider spreads usually mean thinner books or stressed conditions.

### VWAP vs mid-price
- **What it shows:** Two lines per series: `vwap` and `avg_mid_price`.
- **Real meaning:** Execution quality proxy. Large sustained distance suggests impact/slippage or biased flow conditions.

### Cross-exchange close deviation vs instrument average (bps)
- **What it shows:** Each exchange close vs cross-exchange average close **for the same `instrument_id`**, in bps.
- **Real meaning:** Relative pricing dislocation detector; best panel here for spotting anomalies and possible arbitrage windows.

## `tickvault-pipeline-health.json` (Tick Vault - Pipeline Health)

### DLQ count (last 5m)
- **What it shows:** Sum of `dead_letter_count` in recent 5 minutes.
- **Real meaning:** Immediate ingestion/parse failure pressure. Rising value means data-quality or schema handling issues in flight.

### Freshness lag (seconds)
- **What it shows:** Staleness in seconds (`now - max(metric_ts)`).
- **Real meaning:** Pipeline timeliness SLO view; confirms whether market data is current enough for consumers.

### Rows in last 2d
- **What it shows:** Count of recent records over 2 days.
- **Real meaning:** Throughput baseline; used with lag and DLQ to distinguish slow-but-working vs dropped data.

### Latest health rows
- **What it shows:** Recent rows with `instrument_id`, `symbol`, `dead_letter_count`, `anomaly_flag`, `volume`, `spread_bps`, `volatility`.
- **Real meaning:** Fast triage table to inspect whether issues are isolated, broad, or value-specific.

## `tickvault-volatility-heatmap.json` (Tick Vault - Volatility Heatmap)

### Volatility heatmap by hour x instrument
- **What it shows:** Average `volatility` by `hour_of_day` and `exchange:instrument_id` over ~3 days.
- **Real meaning:** Intraday regime map. Identifies when and where volatility structurally concentrates (session overlap effects, exchange-specific behavior).

## `tickvault-exchange-symbol-intelligence.json` (Tick Vault - Exchange & Symbol Intelligence)

### Cross-exchange price divergence by instrument (max-min bps)
- **What it shows:** Per-minute max-min close range in bps, grouped by **`instrument_id`** across selected exchanges.
- **Real meaning:** Dislocation monitor when the same canonical market is priced on multiple venues.

### Top instrument return correlations (1d)
- **What it shows:** Return correlation pairs **`instrument_id`** on the **same exchange** (different instruments).
- **Real meaning:** Within-venue cross-asset correlation screen.

### Instrument anomaly score (last 2h points)
- **What it shows:** Composite z-style score from return, volume, and spread vs rolling stats, keyed by **`exchange` / `instrument_id`** with **`symbol`** for venue context.
- **Real meaning:** Anomaly triage for unusual microstructure behavior.

## Recommended New Reports (Per Exchange and Between Instruments)

### Per-exchange reliability
- **Exchange lag percentiles:** p50/p95 freshness lag by exchange over time.
- **Completeness score:** expected intervals vs actual rows by exchange-instrument-day.
- **DLQ rate:** `SUM(dead_letter_count)/COUNT(*)` by exchange to normalize failures by volume.

### Between exchanges (same instrument)
- **Max-min price divergence (bps):** strongest dislocation monitor.
- **Lead-lag estimator:** short-window return correlations at shifted lags.
- **Spread competitiveness:** percentile spread ranking by venue for one `instrument_id`.

### Between instruments
- **Rolling correlation matrix:** top-N instruments over configurable windows.
- **Relative strength index panel:** normalized cumulative return per instrument.
- **Instrument anomaly score:** z-score composite from return/volume/spread shifts.
- **Pair stability monitor:** rolling spread z-score or cointegration proxy for selected pairs.

## Suggested Rollout Priority

1. Exchange lag percentiles
2. DLQ rate by exchange
3. Max-min price divergence
4. Rolling correlation matrix
5. Instrument anomaly score

This sequence gives immediate operational gains first, then deeper cross-market intelligence.
