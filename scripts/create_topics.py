import os

from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError


def get_env(name: str, default: str) -> str:
    value = os.getenv(name, default)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def main() -> None:
    brokers = get_env("REDPANDA_BROKERS", "redpanda:9092")
    topics = [
        get_env("TRADES_TOPIC", "raw.trades.v1"),
        get_env("DEPTH_TOPIC", "raw.depth.v1"),
        get_env("DLQ_TOPIC", "dlq.trades"),
    ]

    admin = KafkaAdminClient(bootstrap_servers=brokers, client_id="tick-vault-topic-init")
    try:
        for topic in topics:
            try:
                admin.create_topics(
                    new_topics=[NewTopic(name=topic, num_partitions=6, replication_factor=1)],
                    validate_only=False,
                )
                print(f"Created topic: {topic}")
            except TopicAlreadyExistsError:
                print(f"Topic already exists: {topic}")
    finally:
        admin.close()


if __name__ == "__main__":
    main()
