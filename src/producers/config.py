import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    redpanda_brokers: str
    binance_ws_url: str
    binance_symbol: str
    kraken_ws_url: str
    kraken_pair: str
    kraken_book_depth: int
    trades_topic: str
    depth_topic: str
    dlq_topic: str
    reconnect_base_seconds: float
    reconnect_max_seconds: float


def load_settings() -> Settings:
    return Settings(
        redpanda_brokers=os.getenv("REDPANDA_BROKERS", "redpanda:9092"),
        binance_ws_url=os.getenv("BINANCE_WS_URL", "wss://stream.binance.com:9443/ws/btcusdt@trade"),
        binance_symbol=os.getenv("BINANCE_SYMBOL", "BTCUSDT"),
        kraken_ws_url=os.getenv("KRAKEN_WS_URL", "wss://ws.kraken.com"),
        kraken_pair=os.getenv("KRAKEN_PAIR", "XBT/USDT"),
        kraken_book_depth=int(os.getenv("KRAKEN_BOOK_DEPTH", "10")),
        trades_topic=os.getenv("TRADES_TOPIC", "raw.trades.v1"),
        depth_topic=os.getenv("DEPTH_TOPIC", "raw.depth.v1"),
        dlq_topic=os.getenv("DLQ_TOPIC", "dlq.trades"),
        reconnect_base_seconds=float(os.getenv("RECONNECT_BASE_SECONDS", "1")),
        reconnect_max_seconds=float(os.getenv("RECONNECT_MAX_SECONDS", "30")),
    )
