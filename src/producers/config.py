import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    redpanda_brokers: str
    binance_ws_url: str
    binance_symbols: tuple[str, ...]
    kraken_ws_url: str
    kraken_pairs: tuple[str, ...]
    kraken_book_depth: int
    trades_topic: str
    depth_topic: str
    dlq_topic: str
    reconnect_base_seconds: float
    reconnect_max_seconds: float
    coingecko_enabled: bool
    coingecko_topic: str
    coingecko_poll_seconds: float
    coingecko_ids: tuple[str, ...]
    cryptocompare_enabled: bool
    cryptocompare_topic: str
    cryptocompare_poll_seconds: float
    cryptocompare_fsyms: tuple[str, ...]


def _env_bool(name: str, default: str = "true") -> bool:
    return os.getenv(name, default).strip().lower() in ("1", "true", "yes", "on")


def _parse_csv_upper(name: str, default: str) -> tuple[str, ...]:
    raw = os.getenv(name, default)
    parts = [p.strip().upper() for p in raw.split(",") if p.strip()]
    if parts:
        return tuple(parts)
    d = default.strip().upper()
    return (d,) if d else ("BTCUSDT",)


def _parse_csv_preserve(name: str, default: str) -> tuple[str, ...]:
    raw = os.getenv(name, default)
    parts = [p.strip() for p in raw.split(",") if p.strip()]
    if parts:
        return tuple(parts)
    d = default.strip()
    return (d,) if d else ("XBT/USDT",)


def _parse_csv_lower(name: str, default: str) -> tuple[str, ...]:
    raw = os.getenv(name, default)
    parts = [p.strip().lower() for p in raw.split(",") if p.strip()]
    if parts:
        return tuple(parts)
    d = default.strip().lower()
    return (d,) if d else ("bitcoin",)


def _parse_csv_fsym(name: str, default: str) -> tuple[str, ...]:
    raw = os.getenv(name, default)
    parts = [p.strip().upper() for p in raw.split(",") if p.strip()]
    if parts:
        return tuple(parts)
    d = default.strip().upper()
    return (d,) if d else ("BTC",)


def _resolve_binance_ws_url(symbols: tuple[str, ...]) -> str:
    """Derive WS URL from symbols by default; allow explicit override when forced."""
    force_override = _env_bool("BINANCE_WS_FORCE_OVERRIDE", "false")
    explicit = os.getenv("BINANCE_WS_URL")
    if force_override and explicit is not None and (url := explicit.strip()):
        return url
    if len(symbols) == 1:
        return f"wss://stream.binance.com:9443/ws/{symbols[0].lower()}@trade"
    streams = "/".join(f"{s.lower()}@trade" for s in symbols)
    return f"wss://stream.binance.com:9443/stream?streams={streams}"


def load_settings() -> Settings:
    binance_symbols = _parse_csv_upper("BINANCE_SYMBOL", "BTCUSDT")
    return Settings(
        redpanda_brokers=os.getenv("REDPANDA_BROKERS", "redpanda:9092"),
        binance_ws_url=_resolve_binance_ws_url(binance_symbols),
        binance_symbols=binance_symbols,
        kraken_ws_url=os.getenv("KRAKEN_WS_URL", "wss://ws.kraken.com"),
        kraken_pairs=_parse_csv_preserve("KRAKEN_PAIR", "XBT/USDT"),
        kraken_book_depth=int(os.getenv("KRAKEN_BOOK_DEPTH", "10")),
        trades_topic=os.getenv("TRADES_TOPIC", "raw.trades.v1"),
        depth_topic=os.getenv("DEPTH_TOPIC", "raw.depth.v1"),
        dlq_topic=os.getenv("DLQ_TOPIC", "dlq.trades"),
        reconnect_base_seconds=float(os.getenv("RECONNECT_BASE_SECONDS", "1")),
        reconnect_max_seconds=float(os.getenv("RECONNECT_MAX_SECONDS", "30")),
        coingecko_enabled=_env_bool("COINGECKO_ENABLED", "true"),
        coingecko_topic=os.getenv("COINGECKO_TOPIC", "raw.coingecko.v1"),
        coingecko_poll_seconds=float(os.getenv("COINGECKO_POLL_SECONDS", "60")),
        coingecko_ids=_parse_csv_lower("COINGECKO_ID", "bitcoin"),
        cryptocompare_enabled=_env_bool("CRYPTOCOMPARE_ENABLED", "true"),
        cryptocompare_topic=os.getenv("CRYPTOCOMPARE_TOPIC", "raw.cryptocompare.v1"),
        cryptocompare_poll_seconds=float(os.getenv("CRYPTOCOMPARE_POLL_SECONDS", "60")),
        cryptocompare_fsyms=_parse_csv_fsym("CRYPTOCOMPARE_FSYM", "BTC"),
    )
