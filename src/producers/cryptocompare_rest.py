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


async def run_cryptocompare_quotes(settings: Settings, sink: RedpandaSink) -> None:
    url = "https://min-api.cryptocompare.com/data/price"
    while True:
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                r = await client.get(
                    url,
                    params={
                        "fsym": settings.cryptocompare_fsym,
                        "tsyms": "USD",
                    },
                )
                r.raise_for_status()
                raw = r.json()

            usd = raw.get("USD")
            if usd is None:
                raise ValueError(f"unexpected cryptocompare payload: {raw}")

            event_ts_ms = int(time.time() * 1000)
            quote = RestQuoteEvent(
                venue="cryptocompare",
                symbol=settings.cryptocompare_fsym.upper(),
                quote_id=f"cc-{event_ts_ms}-{token_hex(4)}",
                event_ts_ms=event_ts_ms,
                price_usd=Decimal(str(usd)),
                ingest_ts=_now(),
                raw_event=raw,
            )
            sink.send(
                topic=settings.cryptocompare_topic,
                key=f"cryptocompare:{quote.symbol}",
                value=quote.model_dump(mode="json"),
            )
        except (httpx.HTTPError, ValueError, TypeError, ValidationError) as exc:
            dlq = DlqEvent(
                source="cryptocompare.rest",
                reason=f"poll_failed:{exc}",
                raw_payload=str(exc),
            )
            sink.send(topic=settings.dlq_topic, key="cryptocompare.rest", value=dlq.model_dump(mode="json"))

        await asyncio.sleep(max(settings.cryptocompare_poll_seconds, 10.0))
