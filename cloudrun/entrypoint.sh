#!/usr/bin/env bash
# ==============================================================================
# Cloud Run entrypoint — dispatches one image into one of three roles.
#
# Cloud Run contract: the container MUST listen on $PORT (injected, default 8080)
# on 0.0.0.0. Binding a hardcoded port, or binding 127.0.0.1, causes the startup
# probe to fail with no useful error. That is the most common Cloud Run failure.
#
# Roles:
#   api     Cloud Run Service  — FastAPI, public HTTP
#   ui      Cloud Run Service  — Streamlit, public HTTP
#   ingest  Cloud Run Job      — one-off document ingestion, no port
# ==============================================================================
set -euo pipefail

PORT="${PORT:-8080}"
SERVICE_ROLE="${SERVICE_ROLE:-api}"

echo "[entrypoint] role=${SERVICE_ROLE} port=${PORT}"

case "${SERVICE_ROLE}" in
  api)
    # --timeout-graceful-shutdown 5 lets in-flight /query calls drain before
    # Cloud Run SIGKILLs the instance during a scale-in or a new revision.
    exec uvicorn app.main:app \
      --host 0.0.0.0 \
      --port "${PORT}" \
      --timeout-graceful-shutdown 5
    ;;

  ui)
    # Streamlit defaults fight Cloud Run: it tries to open a browser, collects
    # usage stats, and enables XSRF protection that breaks behind the proxy.
    exec streamlit run ui/app.py \
      --server.port "${PORT}" \
      --server.address 0.0.0.0 \
      --server.headless true \
      --server.enableCORS false \
      --server.enableXsrfProtection false \
      --browser.gatherUsageStats false
    ;;

  ingest)
    # Cloud Run Jobs have no port and no request timeout — the right shape for
    # ingestion. INGEST_TARGET/INGEST_WIPE are passed as job env vars.
    TARGET="${INGEST_TARGET:-DATA/true_data}"
    if [ "${INGEST_WIPE:-false}" = "true" ]; then
      exec python -m app.ingestion.processor "${TARGET}" --wipe
    else
      exec python -m app.ingestion.processor "${TARGET}"
    fi
    ;;

  *)
    echo "[entrypoint] FATAL: unknown SERVICE_ROLE '${SERVICE_ROLE}' (expected api|ui|ingest)" >&2
    exit 1
    ;;
esac
