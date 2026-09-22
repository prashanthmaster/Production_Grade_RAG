#!/usr/bin/env bash
# ==============================================================================
# STEP 4 — Deploy the Streamlit UI as a second service from the SAME image.
#
# The only differences from the API service: SERVICE_ROLE=ui (which makes
# entrypoint.sh launch streamlit instead of uvicorn), a smaller instance, and
# BACKEND_URL pointing at the API service.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source cloudrun/config.sh

API_URL="${1:-$(gcloud run services describe "${API_SERVICE}" --region="${REGION}" --format='value(status.url)')}"
if [ -z "${API_URL}" ]; then
  echo "✗ Could not resolve the API URL. Deploy the API first (03_deploy_api.sh)."
  exit 1
fi
echo "▶ UI will call backend: ${API_URL}"

gcloud run deploy "${UI_SERVICE}" \
  --image="${IMAGE}:latest" \
  --region="${REGION}" \
  --service-account="${RUNTIME_SA_EMAIL}" \
  --allow-unauthenticated \
  `# Streamlit is a thin client here — it renders and forwards. The heavy work` \
  `# happens in the API service, so this can be much smaller.` \
  --memory=1Gi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=2 \
  `# Streamlit holds a websocket per browser session, so concurrency is sessions.` \
  --concurrency=20 \
  --timeout=300 \
  --set-env-vars="SERVICE_ROLE=ui,BACKEND_URL=${API_URL},PYTHONUNBUFFERED=1,LOGFIRE_IGNORE_NO_CONFIG=1" \
  `# The UI needs the bearer token to call a protected /query. Same secret,` \
  `# injected into a different service — which is exactly why these live in` \
  `# Secret Manager rather than being baked into the image.` \
  --set-secrets="RAG_API_KEY=rag-api-key:latest"

UI_URL="$(gcloud run services describe "${UI_SERVICE}" --region="${REGION}" --format='value(status.url)')"
echo
echo "✓ UI deployed: ${UI_URL}"
echo "  Open that URL. That is your interview demo."
