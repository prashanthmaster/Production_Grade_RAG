#!/usr/bin/env bash
# ==============================================================================
# STEP 3 Ã¢â‚¬â€ Deploy the FastAPI service.
#
# Every flag below is a deliberate decision. The comments are the interview
# answers; read them before you run this.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source cloudrun/config.sh

gcloud run deploy "${API_SERVICE}" \
  --image="${IMAGE}:latest" \
  --region="${REGION}" \
  --service-account="${RUNTIME_SA_EMAIL}" \
  --allow-unauthenticated \
  \
  `# --- Sizing ---` \
  `# 2Gi: measured need is ~450-650MB (FastAPI + LangChain + LangGraph + NeMo +` \
  `# fastembed). 2Gi leaves headroom for concurrent requests without paying for` \
  `# idle memory, because Cloud Run bills only while a request is in flight.` \
  --memory=2Gi \
  --cpu=2 \
  \
  `# --- Scaling ---` \
  `# min-instances=0 is what makes this deployment effectively free: no traffic,` \
  `# no billing. The cost is a cold start, which the pre-baked guardrails model` \
  `# in Dockerfile.cloudrun exists to minimise.` \
  `# max-instances=5 is a spend ceiling. Each instance can drive OpenAI calls;` \
  `# uncapped autoscaling on a public endpoint is how people wake up to a bill.` \
  --min-instances=0 \
  --max-instances=5 \
  \
  `# --- Concurrency ---` \
  `# Default is 80. The /query path is a SYNCHRONOUS def in FastAPI, so it runs` \
  `# in the threadpool, and each request holds an LLM call open for seconds.` \
  `# 8 keeps per-instance latency sane and lets Cloud Run scale out instead of` \
  `# queueing behind a saturated threadpool.` \
  --concurrency=8 \
  \
  `# --- Timeouts ---` \
  `# A full pipeline run is guardrails + planner + retrieval + rerank + response.` \
  `# 300s is generous; it exists to absorb a slow LLM, not to hide a hang.` \
  --timeout=300 \
  \
  `# --- Cold start ---` \
  `# Uvicorn runs lifespan startup BEFORE it binds the port, and our startup_event` \
  `# builds the Postgres checkpointer, initialises NeMo and probes six services.` \
  `# CPU boost gives the instance full CPU during that window so the port opens` \
  `# before Cloud Run's startup probe gives up.` \
  --cpu-boost \
  --execution-environment=gen2 \
  \
  `# --- Non-sensitive config ---` \
  `# STRICT_STARTUP=false is deliberate. With it true, one transient upstream` \
  `# blip kills the revision at boot and Cloud Run rolls back. The connection` \
  `# checker still runs and still logs; we just do not make a cold start fatal.` \
  `# /ready remains the honest readiness signal for an operator to query.` \
  --set-env-vars="SERVICE_ROLE=api,QDRANT_COLLECTION=enterprise_rag,RATE_LIMIT_PER_MINUTE=60,STRICT_STARTUP=false,PYTHONUNBUFFERED=1,LOGFIRE_IGNORE_NO_CONFIG=1,LANGSMITH_PROJECT=enterprise_rag,LANGSMITH_TRACING=true,PORTKEY_PRIMARY_SLUG=advanced-rag,PORTKEY_FALLBACK_SLUG=anthropic-fallback" \
  \
  `# --- Secrets ---` \
  --set-secrets="OPENAI_API_KEY=openai-api-key:latest,PORTKEY_API_KEY=portkey-api-key:latest,PORTKEY_PRIMARY_CONFIG_ID=portkey-primary-config-id:latest,JINA_API_KEY=jina-api-key:latest,QDRANT_URL=qdrant-url:latest,QDRANT_API_KEY=qdrant-api-key:latest,NEON_DB_URL=neon-db-url:latest,UPSTASH_REDIS_REST_URL=upstash-redis-rest-url:latest,UPSTASH_REDIS_REST_TOKEN=upstash-redis-rest-token:latest,RAG_API_KEY=rag-api-key:latest,LANGSMITH_API_KEY=langsmith-api-key:latest"

API_URL="$(gcloud run services describe "${API_SERVICE}" --region="${REGION}" --format='value(status.url)')"
echo
echo "Ã¢Å“â€œ API deployed: ${API_URL}"
echo
echo "Ã¢â€“Â¶ Smoke test (liveness Ã¢â‚¬â€ should return instantly):"
curl -fsS "${API_URL}/health" && echo
echo "Ã¢â€“Â¶ Readiness (checks all six upstreams Ã¢â‚¬â€ 200 = healthy, 503 = something is down):"
curl -s -o /dev/null -w '  HTTP %{http_code}\n' "${API_URL}/ready"
echo
echo "  Next: ./cloudrun/04_deploy_ui.sh ${API_URL}"
