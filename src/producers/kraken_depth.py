import asyncio
import json
import time
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import websockets
from pydantic import ValidationError

from producers.config import Settings
from producers.redpanda import RedpandaSink
from producers.schemas import DepthLevel, DlqEvent, OrderBookEvent


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_levels(raw_levels: list[list[str]]) -> list[DepthLevel]:
    return [DepthLevel(price=Decimal(level[0]), qty=Decimal(level[1])) for level in raw_levels]


def _extract_book_payload(message: list[Any]) -> dict[str, Any]:
    payload = {}
    for entry in message:
        if isinstance(entry, dict):
            payload.update(entry)
    return payload


def _build_book_event(message: list[Any], pair: str) -> OrderBookEvent:
    payload = _extract_book_payload(message)
    bids = payload.get("b", []) or payload.get("bs", [])
    asks = payload.get("a", []) or payload.get("as", [])
    update_id = str(int(time.time() * 1000))

    return OrderBookEvent(
        venue="kraken",
        symbol=pair,
        update_id=update_id,
        event_ts_ms=int(time.time() * 1000),
        bids=_parse_levels(bids),
        asks=_parse_levels(asks),
        ingest_ts=_now(),
        raw_event={"message": message},
    )


async def run_kraken_depth(settings: Settings, sink: RedpandaSink) -> None:
    subscribe = {
        "event": "subscribe",
        "pair": [settings.kraken_pair],
        "subscription": {"name": "book", "depth": settings.kraken_book_depth},
    }
    backoff = settings.reconnect_base_seconds

    while True:
        try:
            async with websockets.connect(settings.kraken_ws_url, ping_interval=20, ping_timeout=20) as ws:
                print(f"[kraken] connected to {settings.kraken_ws_url}")
                backoff = settings.reconnect_base_seconds
                await ws.send(json.dumps(subscribe))

                async for message in ws:
                    try:
                        raw = json.loads(message)
                        if isinstance(raw, dict):
                            continue
                        if not isinstance(raw, list) or len(raw) < 2:
                            continue

                        book = _build_book_event(raw, settings.kraken_pair)
                        sink.send(
                            topic=settings.depth_topic,
                            key=f"kraken:{book.symbol}",
                            value=book.model_dump(mode="json"),
                        )
                    except (json.JSONDecodeError, ValidationError, ValueError, TypeError, IndexError) as exc:
                        dlq = DlqEvent(
                            source="kraken.depth",
                            reason=f"schema_validation_failed:{exc}",
                            raw_payload=message,
                        )
                        sink.send(
                            topic=settings.dlq_topic,
                            key="kraken.depth",
                            value=dlq.model_dump(mode="json"),
                        )
        except Exception as exc:  # noqa: BLE001 - keep stream alive in producer runtime
            print(f"[kraken] disconnected: {exc}. reconnecting in {backoff}s")
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, settings.reconnect_max_seconds)
