"""
PyFlink Table job: Redpanda (Kafka) raw topics -> Hive-partitioned Parquet on object storage.

Local compose targets MinIO via s3a://. Production targets gs:// with GCS credentials on the cluster.
"""

from __future__ import annotations

import os

from pyflink.table import EnvironmentSettings, TableEnvironment


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default).strip()


def main() -> None:
    kafka_brokers = _env("KAFKA_BOOTSTRAP_SERVERS", "redpanda:9092")
    trades_topic = _env("TRADES_TOPIC", "raw.trades.v1")
    depth_topic = _env("DEPTH_TOPIC", "raw.depth.v1")
    coingecko_topic = _env("COINGECKO_TOPIC", "raw.coingecko.v1")
    cryptocompare_topic = _env("CRYPTOCOMPARE_TOPIC", "raw.cryptocompare.v1")
    sink_base = _env("BRONZE_SINK_BASE", "s3a://tick-vault/bronze").rstrip("/")
    checkpoint_dir = _env("CHECKPOINT_DIR", "s3a://tick-vault/flink-checkpoints").rstrip("/")
    group_trades = _env("FLINK_KAFKA_GROUP_TRADES", "flink-bronze-trades")
    group_depth = _env("FLINK_KAFKA_GROUP_DEPTH", "flink-bronze-depth")
    group_coingecko = _env("FLINK_KAFKA_GROUP_COINGECKO", "flink-bronze-coingecko")
    group_cryptocompare = _env("FLINK_KAFKA_GROUP_CRYPTOCOMPARE", "flink-bronze-cryptocompare")
    startup_mode = _env("KAFKA_SCAN_STARTUP_MODE", "earliest-offset")
    checkpoint_interval_ms = int(_env("CHECKPOINT_INTERVAL_MS", "120000"))

    settings = EnvironmentSettings.in_streaming_mode()
    t_env = TableEnvironment.create(settings)
    conf = t_env.get_config().get_configuration()
    conf.set_string("table.exec.sink.not-null-enforcer", "DROP")
    conf.set_string("execution.checkpointing.interval", str(checkpoint_interval_ms))
    conf.set_string("state.checkpoints.dir", checkpoint_dir)
    conf.set_string("execution.checkpointing.mode", "AT_LEAST_ONCE")
    conf.set_string("table.local-time-zone", "UTC")

    t_env.execute_sql(
        f"""
        CREATE TABLE kafka_trades (
          `payload` STRING,
          `kafka_topic` STRING METADATA FROM 'topic' VIRTUAL,
          `kafka_partition` INT METADATA FROM 'partition' VIRTUAL,
          `kafka_offset` BIGINT METADATA FROM 'offset' VIRTUAL,
          `kafka_ts` TIMESTAMP(3) METADATA FROM 'timestamp' VIRTUAL
        ) WITH (
          'connector' = 'kafka',
          'topic' = '{trades_topic}',
          'properties.bootstrap.servers' = '{kafka_brokers}',
          'properties.group.id' = '{group_trades}',
          'scan.startup.mode' = '{startup_mode}',
          'format' = 'raw'
        )
        """
    )

    t_env.execute_sql(
        f"""
        CREATE TABLE kafka_depth (
          `payload` STRING,
          `kafka_topic` STRING METADATA FROM 'topic' VIRTUAL,
          `kafka_partition` INT METADATA FROM 'partition' VIRTUAL,
          `kafka_offset` BIGINT METADATA FROM 'offset' VIRTUAL,
          `kafka_ts` TIMESTAMP(3) METADATA FROM 'timestamp' VIRTUAL
        ) WITH (
          'connector' = 'kafka',
          'topic' = '{depth_topic}',
          'properties.bootstrap.servers' = '{kafka_brokers}',
          'properties.group.id' = '{group_depth}',
          'scan.startup.mode' = '{startup_mode}',
          'format' = 'raw'
        )
        """
    )

    t_env.execute_sql(
        f"""
        CREATE TABLE kafka_coingecko (
          `payload` STRING,
          `kafka_topic` STRING METADATA FROM 'topic' VIRTUAL,
          `kafka_partition` INT METADATA FROM 'partition' VIRTUAL,
          `kafka_offset` BIGINT METADATA FROM 'offset' VIRTUAL,
          `kafka_ts` TIMESTAMP(3) METADATA FROM 'timestamp' VIRTUAL
        ) WITH (
          'connector' = 'kafka',
          'topic' = '{coingecko_topic}',
          'properties.bootstrap.servers' = '{kafka_brokers}',
          'properties.group.id' = '{group_coingecko}',
          'scan.startup.mode' = '{startup_mode}',
          'format' = 'raw'
        )
        """
    )

    t_env.execute_sql(
        f"""
        CREATE TABLE kafka_cryptocompare (
          `payload` STRING,
          `kafka_topic` STRING METADATA FROM 'topic' VIRTUAL,
          `kafka_partition` INT METADATA FROM 'partition' VIRTUAL,
          `kafka_offset` BIGINT METADATA FROM 'offset' VIRTUAL,
          `kafka_ts` TIMESTAMP(3) METADATA FROM 'timestamp' VIRTUAL
        ) WITH (
          'connector' = 'kafka',
          'topic' = '{cryptocompare_topic}',
          'properties.bootstrap.servers' = '{kafka_brokers}',
          'properties.group.id' = '{group_cryptocompare}',
          'scan.startup.mode' = '{startup_mode}',
          'format' = 'raw'
        )
        """
    )

    t_env.execute_sql(
        f"""
        CREATE TABLE bronze_parquet (
          `stream_kind` STRING,
          `payload` STRING,
          `exchange` STRING,
          `symbol` STRING,
          `event_ts_ms` BIGINT,
          `ingest_ts` STRING,
          `kafka_topic` STRING,
          `kafka_partition` INT,
          `kafka_offset` BIGINT,
          `kafka_ts` TIMESTAMP(3),
          `dt` STRING
        ) PARTITIONED BY (`dt`, `symbol`, `exchange`) WITH (
          'connector' = 'filesystem',
          'path' = '{sink_base}/',
          'format' = 'parquet',
          'sink.partition-commit.policy.kind' = 'success-file',
          'sink.partition-commit.trigger' = 'process-time',
          'sink.partition-commit.delay' = '1 min',
          'sink.rolling-policy.file-size' = '64MB',
          'sink.rolling-policy.rollover-interval' = '5 min'
        )
        """
    )

    row_select = """
      `payload`,
      COALESCE(JSON_VALUE(`payload`, '$.venue'), 'unknown') AS exchange,
      COALESCE(
        REPLACE(REPLACE(JSON_VALUE(`payload`, '$.symbol'), '/', '-'), ':', '_'),
        'unknown'
      ) AS symbol,
      TRY_CAST(JSON_VALUE(`payload`, '$.event_ts_ms') AS BIGINT) AS event_ts_ms,
      JSON_VALUE(`payload`, '$.ingest_ts') AS ingest_ts,
      `kafka_topic`,
      `kafka_partition`,
      `kafka_offset`,
      `kafka_ts`,
      DATE_FORMAT(
        COALESCE(
          TO_TIMESTAMP_LTZ(TRY_CAST(JSON_VALUE(`payload`, '$.event_ts_ms') AS BIGINT), 3),
          CAST(`kafka_ts` AS TIMESTAMP_LTZ(3))
        ),
        'yyyy-MM-dd'
      ) AS dt
    """

    insert_sql = f"""
    INSERT INTO bronze_parquet
    SELECT
      'trades' AS stream_kind,
      {row_select}
    FROM kafka_trades
    UNION ALL
    SELECT
      'depth' AS stream_kind,
      {row_select}
    FROM kafka_depth
    UNION ALL
    SELECT
      'coingecko' AS stream_kind,
      {row_select}
    FROM kafka_coingecko
    UNION ALL
    SELECT
      'cryptocompare' AS stream_kind,
      {row_select}
    FROM kafka_cryptocompare
    """

    table_result = t_env.execute_sql(insert_sql)
    job_client = table_result.get_job_client()
    if job_client is not None:
        print(f"bronze_sink_job submitted job_id={job_client.get_job_id()}")
    # Do not wait(): streaming job runs on the cluster; `flink run -d` also detaches the CLI.


if __name__ == "__main__":
    main()
