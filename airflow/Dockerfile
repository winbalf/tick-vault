# Extends official Airflow with gcloud/bq, Docker CLI (for mc mirror via host socket), and dbt-bigquery.
# Build context: repository root (.. when compose sets context).
FROM apache/airflow:2.8.4-python3.11

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends gnupg curl ca-certificates apt-transport-https \
  && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/google-cloud.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends google-cloud-cli \
  && apt-get install -y --no-install-recommends docker.io \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/google-cloud-sdk/bin:${PATH}"

USER airflow
RUN pip install --no-cache-dir "dbt-bigquery>=1.8.0,<1.9.0"
