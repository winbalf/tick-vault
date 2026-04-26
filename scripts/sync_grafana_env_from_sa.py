#!/usr/bin/env python3
"""Merge GCP_PROJECT_ID, GCP_CLIENT_EMAIL, and GCP_TOKEN_URI into .env from a service account JSON.

The Grafana container reads the **private key** from ``keys/gcs.json`` mounted at
``/etc/grafana/sa.json`` (see ``docker-compose.yml``). Docker Compose cannot pass a
PEM reliably through ``.env`` (backslash/newline and ``sed`` replacement issues), so
this script does **not** write ``GCP_PRIVATE_KEY`` to ``.env``.

Usage:
  python3 scripts/sync_grafana_env_from_sa.py
  python3 scripts/sync_grafana_env_from_sa.py --sa-json keys/gcs.json --env-file .env
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def merge_env(env_path: Path, sa: dict[str, object]) -> None:
    required = ("project_id", "client_email", "token_uri")
    for k in required:
        if k not in sa:
            raise SystemExit(f"service account JSON missing {k!r}")

    token_uri = str(sa["token_uri"])
    project_id = str(sa["project_id"])
    client_email = str(sa["client_email"])

    env_lines = env_path.read_text().splitlines(keepends=True) if env_path.exists() else []

    strip = re.compile(
        r"^(GCP_PROJECT_ID|GCP_CLIENT_EMAIL|GCP_TOKEN_URI|GCP_PRIVATE_KEY)="
    )
    filtered = [ln for ln in env_lines if not strip.match(ln.lstrip())]

    block_lines = [
        "# Grafana / BigQuery (from keys/gcs.json; rerun: python3 scripts/sync_grafana_env_from_sa.py)",
        "# Private key is NOT in .env — mount keys/gcs.json as /etc/grafana/sa.json (see docker-compose).",
        f"GCP_PROJECT_ID={project_id}",
        f"GCP_CLIENT_EMAIL={client_email}",
        f"GCP_TOKEN_URI={token_uri}",
        "",
    ]

    body = "".join(filtered)
    if body and not body.endswith("\n"):
        body += "\n"
    env_path.write_text(body + "\n".join(block_lines))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sa-json",
        type=Path,
        default=Path("keys/gcs.json"),
        help="Path to service account JSON",
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=Path(".env"),
        help="Path to .env to update",
    )
    args = parser.parse_args()

    if not args.sa_json.is_file():
        raise SystemExit(f"not found: {args.sa_json}")

    sa = json.loads(args.sa_json.read_text(encoding="utf-8"))
    merge_env(args.env_file, sa)
    print(
        f"Updated {args.env_file} with GCP_PROJECT_ID, GCP_CLIENT_EMAIL, GCP_TOKEN_URI "
        f"(private key stays in {args.sa_json}; use compose mount for Grafana)."
    )


if __name__ == "__main__":
    main()
