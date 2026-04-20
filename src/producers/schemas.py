from datetime import datetime, timezone
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class TradeEvent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    venue: str = Field(min_length=1)
    symbol: str = Field(min_length=1)
    trade_id: str = Field(min_length=1)
    event_ts_ms: int
    price: Decimal
    quantity: Decimal
    is_buyer_maker: bool
    ingest_ts: datetime
    raw_event: dict


class DepthLevel(BaseModel):
    model_config = ConfigDict(extra="forbid")

    price: Decimal
    qty: Decimal


class OrderBookEvent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    venue: str = Field(min_length=1)
    symbol: str = Field(min_length=1)
    update_id: str = Field(min_length=1)
    event_ts_ms: int
    bids: list[DepthLevel]
    asks: list[DepthLevel]
    ingest_ts: datetime
    raw_event: dict


class RestQuoteEvent(BaseModel):
    """Periodic REST quote (CoinGecko, CryptoCompare) published to raw.* topics for bronze."""

    model_config = ConfigDict(extra="forbid")

    venue: str = Field(..., min_length=1)
    symbol: str = Field(..., min_length=1)
    quote_id: str = Field(..., min_length=1)
    event_ts_ms: int
    price_usd: Decimal
    ingest_ts: datetime
    raw_event: dict


class DlqEvent(BaseModel):
    model_config = ConfigDict(extra="allow")

    source: str = Field(min_length=1)
    reason: str = Field(min_length=1)
    raw_payload: dict | str
    ingest_ts: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
