# Tick Vault Grafana Dashboards - Full Report Meaning Guide

This document summarizes every current dashboard in `docker/grafana/dashboards/*.json`, what each report shows, and its real operational meaning.

## `tickvault-debug.json` (Tick Vault - Debug BigQuery)

### BigQuery connection
- **What it shows:** Always returns `1` when Grafana can execute a simple query.
- **Real meaning:** Data source/auth/connectivity heartbeat. If red, root cause is likely infra/permissions rather than market logic.

### fct_market_metrics exists
- **What it shows:** `1` if `${gold_dataset}.fct_market_metrics` exists.
- **Real meaning:** Schema deployment guardrail. If `0`, pipeline may be running but this dashboard has no target table.

### Rows in last 2d
- **What it shows:** 2-day row count for selected `exchange` and `symbol`.
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

### Rows by exchange/symbol (2d)
- **What it shows:** Per `(exchange, symbol)` count and latest timestamp over 2 days.
- **Real meaning:** Coverage map to detect silent partial failures (one venue stale while others are healthy).

### Latest 100 rows
- **What it shows:** Last records with `close`, `volume`, `spread_bps`, `volatility`, `dead_letter_count`.
- **Real meaning:** Ground-truth sample for spot-checking value plausibility and troubleshooting anomalies.

## `tickvault-overview.json` (Tick Vault - Live Price & Volume)

### Live candlestick
- **What it shows:** OHLC candles (`open/high/low/close`) over last 2 days.
- **Real meaning:** Market structure view. Useful for trend/reversal context and validating that price formation is coherent.

### Live traded volume by symbol
- **What it shows:** Time-series bars of `volume` per `exchange:symbol`.
- **Real meaning:** Liquidity/activity monitor. Spikes signal participation bursts; flatlines can indicate feed or venue interruptions.

### Cross-exchange close price (same symbol)
- **What it shows:** `close` by exchange for one symbol.
- **Real meaning:** Venue consistency panel. Persistent divergence can imply latency asymmetry, microstructure differences, or bad ticks.

## `tickvault-spread-vwap.json` (Tick Vault - Spread & VWAP)

### Bid-ask spread over time
- **What it shows:** `spread_bps` time series by `exchange:symbol`.
- **Real meaning:** Tradability/liquidity cost signal. Wider spreads usually mean thinner books or stressed conditions.

### VWAP vs mid-price
- **What it shows:** Two lines per series: `vwap` and `avg_mid_price`.
- **Real meaning:** Execution quality proxy. Large sustained distance suggests impact/slippage or biased flow conditions.

### Cross-exchange close deviation vs symbol average (bps)
- **What it shows:** Each exchange close vs cross-exchange average close, in bps.
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
- **What it shows:** Recent rows with `dead_letter_count`, `anomaly_flag`, `volume`, `spread_bps`, `volatility`.
- **Real meaning:** Fast triage table to inspect whether issues are isolated, broad, or value-specific.

## `tickvault-volatility-heatmap.json` (Tick Vault - Volatility Heatmap)

### Volatility heatmap by hour x symbol
- **What it shows:** Average `volatility` by `hour_of_day` and `exchange:symbol` over ~3 days.
- **Real meaning:** Intraday regime map. Identifies when and where volatility structurally concentrates (session overlap effects, exchange-specific behavior).

## Recommended New Reports (Per Exchange and Between Symbols)

### Per-exchange reliability
- **Exchange lag percentiles:** p50/p95 freshness lag by exchange over time.
- **Completeness score:** expected intervals vs actual rows by exchange-symbol-day.
- **DLQ rate:** `SUM(dead_letter_count)/COUNT(*)` by exchange to normalize failures by volume.

### Between exchanges (same symbol)
- **Max-min price divergence (bps):** strongest dislocation monitor.
- **Lead-lag estimator:** short-window return correlations at shifted lags.
- **Spread competitiveness:** percentile spread ranking by venue for one symbol.

### Between symbols
- **Rolling correlation matrix:** top-N symbols over configurable windows.
- **Relative strength index panel:** normalized cumulative return per symbol.
- **Symbol anomaly score:** z-score composite from return/volume/spread shifts.
- **Pair stability monitor:** rolling spread z-score or cointegration proxy for selected pairs.

## Suggested Rollout Priority

1. Exchange lag percentiles
2. DLQ rate by exchange
3. Max-min price divergence
4. Rolling correlation matrix
5. Symbol anomaly score

This sequence gives immediate operational gains first, then deeper cross-market intelligence.
