#!/usr/bin/env python3
"""
Compare Kafka high-water offsets (approximate published events) with Parquet row counts.

Notes
-----
- Kafka high water marks count retained log segments only; compaction or retention can shrink history.
- Flink AT_LEAST_ONCE can duplicate rows after failures; expect Parquet >= Kafka in edge cases.
- While the Flink job is catching up, Parquet will lag Kafka until checkpoints + partition commits finish.

Install tooling:
    pip install -r requirements-bronze-tools.txt
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from typing import Iterable

try:
    from kafka import KafkaConsumer
except ImportError as exc:  # pragma: no cover - import guard
    raise SystemExit("kafka-python is required. pip install -r requirements-bronze-tools.txt") from exc


def _sum_end_offsets(bootstrap: str, topics: Iterable[str], group_id: str) -> dict[str, int]:
    consumer = KafkaConsumer(
        bootstrap_servers=bootstrap,
        group_id=group_id,
        enable_auto_commit=False,
        consumer_timeout_ms=5000,
    )
    consumer.subscribe(list(topics))
    # Force partition assignment
    consumer.poll(timeout_ms=5000)
    partitions = consumer.assignment()
    if not partitions:
        consumer.close()
        return {t: 0 for t in topics}

    end_offsets = consumer.end_offsets(partitions)
    per_topic: dict[str, int] = defaultdict(int)
    for tp, hi in end_offsets.items():
        per_topic[tp.topic] += int(hi)

    consumer.close()
    return dict(per_topic)


def _count_parquet_s3(prefix_uri: str) -> int:
    try:
        import pyarrow.dataset as ds  # type: ignore[import-not-found]
        import pyarrow.fs as pafs  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - import guard
        raise SystemExit("pyarrow is required for --parquet-s3-prefix. pip install -r requirements-bronze-tools.txt") from exc

    # prefix_uri examples:
    #   s3://tick-vault/bronze  (MinIO via pyarrow S3FileSystem + endpoint override)
    #   gs://bucket/bronze      (GCS via gcsfs / pyarrow; not wired here—use BigQuery COUNT instead)
    if not prefix_uri.startswith("s3://"):
        raise SystemExit("Only s3:// prefixes are supported for local MinIO validation in this script.")

    without = prefix_uri[len("s3://") :]
    bucket, _, prefix = without.partition("/")
    access_key = os.environ.get("S3_ACCESS_KEY", "minioadmin")
    secret_key = os.environ.get("S3_SECRET_KEY", "minioadmin")
    endpoint = os.environ.get("S3_ENDPOINT", "http://127.0.0.1:9000")

    filesystem = pafs.S3FileSystem(
        access_key=access_key,
        secret_key=secret_key,
        endpoint_override=endpoint,
        scheme="http" if endpoint.startswith("http://") else "https",
    )
    dataset = ds.dataset(f"{bucket}/{prefix}", filesystem=filesystem, format="parquet")
    return int(dataset.scanner().count_rows())


def _count_bigquery(table_fqn: str) -> int:
    try:
        from google.cloud import bigquery  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - import guard
        raise SystemExit("google-cloud-bigquery is required for --bigquery-table.") from exc

    client = bigquery.Client()
    job = client.query(f"SELECT COUNT(1) AS c FROM `{table_fqn}`")
    rows = list(job.result())
    return int(rows[0]["c"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kafka-bootstrap", default=os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:19092"))
    parser.add_argument(
        "--topics",
        nargs="+",
        default=["raw.trades.v1", "raw.depth.v1"],
        help="Kafka topics whose end offsets are summed.",
    )
    parser.add_argument("--group-id", default="validate-bronze-offsets")
    parser.add_argument(
        "--parquet-s3-prefix",
        help="MinIO/S3A style prefix, e.g. s3://tick-vault/bronze (uses S3_* env vars for credentials).",
    )
    parser.add_argument("--bigquery-table", help="Fully qualified table id project.dataset.table for COUNT(*).")
    args = parser.parse_args()

    offsets = _sum_end_offsets(args.kafka_bootstrap, args.topics, args.group_id)
    kafka_total = sum(offsets.values())

    print(json.dumps({"kafka_end_offsets_by_topic": offsets, "kafka_total_end_offset_sum": kafka_total}, indent=2))

    if args.parquet_s3_prefix:
        rows = _count_parquet_s3(args.parquet_s3_prefix)
        print(json.dumps({"parquet_row_count": rows, "delta_parquet_minus_kafka": rows - kafka_total}, indent=2))

    if args.bigquery_table:
        rows_bq = _count_bigquery(args.bigquery_table)
        print(json.dumps({"bigquery_row_count": rows_bq, "delta_bq_minus_kafka": rows_bq - kafka_total}, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
