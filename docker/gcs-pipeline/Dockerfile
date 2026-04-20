# Used by docker compose profile "gcs": MinIO → GCS sync + BigQuery bronze bootstrap (mc + gcloud + bq).
FROM google/cloud-sdk:alpine

RUN apk add --no-cache bash curl ca-certificates \
  && curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
  && chmod +x /usr/local/bin/mc
