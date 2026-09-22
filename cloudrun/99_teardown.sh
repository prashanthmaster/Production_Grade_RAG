#!/usr/bin/env bash
# ==============================================================================
# TEARDOWN — remove everything this deployment created.
#
# Run this after the interview. Cloud Run at min-instances=0 costs ~nothing
# idle, but Artifact Registry storage and Secret Manager versions do accrue
# small charges, and an unused project is an unmonitored attack surface.
#
# Usage:
#   ./cloudrun/99_teardown.sh            # remove services, keep the project
#   ./cloudrun/99_teardown.sh --nuke     # delete the entire project
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source cloudrun/config.sh

if [ "${1:-}" = "--nuke" ]; then
  echo "▶ Deleting project ${PROJECT_ID} in its entirety."
  echo "  This is irreversible and removes every resource, secret and log."
  read -r -p "  Type the project ID to confirm: " CONFIRM
  [ "${CONFIRM}" = "${PROJECT_ID}" ] || { echo "✗ Mismatch — aborted."; exit 1; }
  gcloud projects delete "${PROJECT_ID}"
  echo "✓ Project scheduled for deletion (30-day recovery window)."
  exit 0
fi

echo "▶ Removing Cloud Run services"
gcloud run services delete "${UI_SERVICE}"  --region="${REGION}" --quiet 2>/dev/null || true
gcloud run services delete "${API_SERVICE}" --region="${REGION}" --quiet 2>/dev/null || true

echo "▶ Removing container images"
gcloud artifacts repositories delete "${REPO}" --location="${REGION}" --quiet 2>/dev/null || true

echo "▶ Removing secrets"
for s in openai-api-key portkey-api-key portkey-primary-config-id jina-api-key \
         qdrant-url qdrant-api-key neon-db-url upstash-redis-rest-url \
         upstash-redis-rest-token rag-api-key langsmith-api-key; do
  gcloud secrets delete "${s}" --quiet 2>/dev/null || true
done

echo "▶ Removing runtime service account"
gcloud iam service-accounts delete "${RUNTIME_SA_EMAIL}" --quiet 2>/dev/null || true

echo
echo "✓ Teardown complete. The project shell remains (free)."
echo "  Remember to also delete: Qdrant cluster, Neon project, Upstash DB."
