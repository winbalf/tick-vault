import asyncio
import json
from datetime import datetime, timezone
from decimal import Decimal

import websockets
from pydantic import ValidationError

from producers.config import Settings
from producers.redpanda import RedpandaSink
from producers.schemas import DlqEvent, TradeEvent


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _unwrap_combined_stream(raw: dict) -> tuple[dict, str | None]:
    """Binance combined streams wrap payloads as {stream, data}; single stream sends the trade dict directly."""
    inner = raw.get("data")
    if isinstance(inner, dict) and "stream" in raw:
        stream = str(raw["stream"])
        hint = stream.split("@")[0].upper() if "@" in stream else None
        return inner, hint
    return raw, None


def _parse_trade(raw: dict, symbol: str) -> TradeEvent:
    return TradeEvent(
        venue="binance",
        symbol=symbol,
        trade_id=str(raw["t"]),
        event_ts_ms=int(raw["E"]),
        price=Decimal(raw["p"]),
        quantity=Decimal(raw["q"]),
        is_buyer_maker=bool(raw["m"]),
        ingest_ts=_now(),
        raw_event=raw,
    )


async def run_binance_trades(settings: Settings, sink: RedpandaSink) -> None:
    backoff = settings.reconnect_base_seconds
    fallback_symbol = settings.binance_symbols[0]
    while True:
        try:
            async with websockets.connect(settings.binance_ws_url, ping_interval=20, ping_timeout=20) as ws:
                print(f"[binance] connected to {settings.binance_ws_url} symbols={settings.binance_symbols}")
                backoff = settings.reconnect_base_seconds

                async for message in ws:
                    try:
                        raw = json.loads(message)
                        payload, stream_sym = _unwrap_combined_stream(raw)
                        sym = (
                            str(payload.get("s")).upper()
                            if payload.get("s")
                            else (stream_sym or fallback_symbol)
                        )
                        trade = _parse_trade(raw=payload, symbol=sym)
                        sink.send(
                            topic=settings.trades_topic,
                            key=f"binance:{trade.symbol}",
                            value=trade.model_dump(mode="json"),
                        )
                    except (json.JSONDecodeError, KeyError, TypeError, ValueError, ValidationError) as exc:
                        dlq = DlqEvent(
                            source="binance.trades",
                            reason=f"schema_validation_failed:{exc}",
                            raw_payload=message,
                        )
                        sink.send(
                            topic=settings.dlq_topic,
                            key="binance.trades",
                            value=dlq.model_dump(mode="json"),
                        )
        except Exception as exc:  # noqa: BLE001 - keep stream alive in producer runtime
            print(f"[binance] disconnected: {exc}. reconnecting in {backoff}s")
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, settings.reconnect_max_seconds)
