import asyncio
import time
from datetime import datetime, timezone
from decimal import Decimal
from secrets import token_hex

import httpx
from pydantic import ValidationError

from producers.config import Settings
from producers.redpanda import RedpandaSink
from producers.schemas import DlqEvent, RestQuoteEvent


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _symbol_for_id(coin_id: str) -> str:
    mapping = {
        "bitcoin": "BTC",
        "ethereum": "ETH",
    }
    return mapping.get(coin_id.lower(), coin_id.replace("-", "_").upper()[:32])


async def run_coingecko_quotes(settings: Settings, sink: RedpandaSink) -> None:
    url = "https://api.coingecko.com/api/v3/simple/price"
    while True:
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                r = await client.get(
                    url,
                    params={
                        "ids": settings.coingecko_id,
                        "vs_currencies": "usd",
                    },
                )
                r.raise_for_status()
                raw = r.json()

            coin = settings.coingecko_id
            inner = raw.get(coin) or raw.get(coin.lower()) or {}
            usd = inner.get("usd") if isinstance(inner, dict) else None
            if usd is None:
                raise ValueError(f"unexpected coingecko payload keys={list(raw.keys())}")

            event_ts_ms = int(time.time() * 1000)
            quote = RestQuoteEvent(
                venue="coingecko",
                symbol=_symbol_for_id(coin),
                quote_id=f"cg-{event_ts_ms}-{token_hex(4)}",
                event_ts_ms=event_ts_ms,
                price_usd=Decimal(str(usd)),
                ingest_ts=_now(),
                raw_event=raw,
            )
            sink.send(
                topic=settings.coingecko_topic,
                key=f"coingecko:{quote.symbol}",
                value=quote.model_dump(mode="json"),
            )
        except (httpx.HTTPError, ValueError, TypeError, ValidationError) as exc:
            dlq = DlqEvent(
                source="coingecko.rest",
                reason=f"poll_failed:{exc}",
                raw_payload=str(exc),
            )
            sink.send(topic=settings.dlq_topic, key="coingecko.rest", value=dlq.model_dump(mode="json"))

        await asyncio.sleep(max(settings.coingecko_poll_seconds, 10.0))
