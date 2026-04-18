FROM maven:3.9.9-eclipse-temurin-17 AS parquet-deps
WORKDIR /deps
COPY docker/flink/pom-parquet-deps.xml pom.xml
RUN mvn -q -B dependency:copy-dependencies -DoutputDirectory=/deps/out

FROM flink:1.19.1-scala_2.12-java17

ARG FLINK_VERSION=1.19.1

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip curl ca-certificates \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir apache-flink==1.19.1

COPY --from=parquet-deps /deps/out/ /opt/flink/lib/
# Hadoop 2.10.x pulls commons-cli 1.2 which breaks Flink 1.19 (needs Option.builder); keep 1.6 from Maven only.
RUN rm -f /opt/flink/lib/commons-cli-1.2.jar

RUN mkdir -p /opt/flink/scripts \
    && curl -fsSL -o /opt/flink/lib/flink-sql-connector-kafka-3.3.0-1.19.jar \
        https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.3.0-1.19/flink-sql-connector-kafka-3.3.0-1.19.jar \
    && cp "/opt/flink/opt/flink-s3-fs-hadoop-${FLINK_VERSION}.jar" /opt/flink/lib/ \
    && if [ -f "/opt/flink/opt/flink-gs-fs-hadoop-${FLINK_VERSION}.jar" ]; then \
         cp "/opt/flink/opt/flink-gs-fs-hadoop-${FLINK_VERSION}.jar" /opt/flink/lib/; \
       fi

COPY docker/flink/scripts/wait_and_submit.sh /opt/flink/scripts/wait_and_submit.sh
RUN chmod +x /opt/flink/scripts/wait_and_submit.sh

COPY src/flink_jobs /opt/flink/usrlib/python/flink_jobs

ENV PYTHONPATH=/opt/flink/usrlib/python

USER flink
