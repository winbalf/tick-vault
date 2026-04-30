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
    while True:
        try:
            fsyms = settings.cryptocompare_fsyms
            multi = len(fsyms) > 1
            url = (
                "https://min-api.cryptocompare.com/data/pricemulti"
                if multi
                else "https://min-api.cryptocompare.com/data/price"
            )
            async with httpx.AsyncClient(timeout=30.0) as client:
                if multi:
                    r = await client.get(
                        url,
                        params={
                            "fsyms": ",".join(fsyms),
                            "tsyms": "USD",
                        },
                    )
                else:
                    r = await client.get(
                        url,
                        params={
                            "fsym": fsyms[0],
                            "tsyms": "USD",
                        },
                    )
                r.raise_for_status()
                raw = r.json()

            event_ts_ms = int(time.time() * 1000)
            if multi:
                if not isinstance(raw, dict):
                    raise ValueError(f"unexpected cryptocompare payload: {raw}")
                for fsym in fsyms:
                    inner = raw.get(fsym) or raw.get(fsym.upper())
                    if not isinstance(inner, dict):
                        raise ValueError(f"missing quote for {fsym!r} in {raw}")
                    usd = inner.get("USD")
                    if usd is None:
                        raise ValueError(f"missing USD for {fsym!r} in {raw}")
                    sym = fsym.upper()
                    quote = RestQuoteEvent(
                        venue="cryptocompare",
                        symbol=sym,
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
            else:
                usd = raw.get("USD")
                if usd is None:
                    raise ValueError(f"unexpected cryptocompare payload: {raw}")
                sym = fsyms[0].upper()
                quote = RestQuoteEvent(
                    venue="cryptocompare",
                    symbol=sym,
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
