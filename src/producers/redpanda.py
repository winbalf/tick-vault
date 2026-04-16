import json
from typing import Any

from kafka import KafkaProducer


class RedpandaSink:
    def __init__(self, bootstrap_servers: str, acks: str = "all") -> None:
        self.producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            acks=acks,
            compression_type="gzip",
            linger_ms=10,
            value_serializer=lambda x: json.dumps(x, separators=(",", ":")).encode("utf-8"),
            key_serializer=lambda x: x.encode("utf-8") if isinstance(x, str) else x,
        )

    def send(self, topic: str, value: dict[str, Any], key: str | None = None) -> None:
        self.producer.send(topic, value=value, key=key)

    def flush(self) -> None:
        self.producer.flush()

    def close(self) -> None:
        self.producer.flush()
        self.producer.close()
