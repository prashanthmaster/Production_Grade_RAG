#!/usr/bin/env bash
# ==============================================================================
# STEP 1 — Push .env into Secret Manager and grant the runtime identity access.
#
# Why not just --set-env-vars for everything? Because plain env vars on a Cloud
# Run revision are visible to anyone with Viewer on the project, and they show
# up in `gcloud run services describe` output and in deployment logs. Secrets
# are versioned, access-controlled and auditable. Only non-sensitive config
# (collection name, rate limit, service role) goes in as a plain env var.
#
# Idempotent: re-running adds a new secret VERSION rather than failing.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source cloudrun/config.sh

if [ ! -f .env ]; then
  echo "✗ .env not found. Fill it in first — see KEYS_SETUP.md"
  exit 1
fi

# Secrets to create, in the form ENV_VAR_NAME:secret-manager-id
SECRETS=(
  "OPENAI_API_KEY:openai-api-key"
  "PORTKEY_API_KEY:portkey-api-key"
  "PORTKEY_PRIMARY_CONFIG_ID:portkey-primary-config-id"
  "JINA_API_KEY:jina-api-key"
  "QDRANT_URL:qdrant-url"
  "QDRANT_API_KEY:qdrant-api-key"
  "NEON_DB_URL:neon-db-url"
  "UPSTASH_REDIS_REST_URL:upstash-redis-rest-url"
  "UPSTASH_REDIS_REST_TOKEN:upstash-redis-rest-token"
  "RAG_API_KEY:rag-api-key"
  "LANGSMITH_API_KEY:langsmith-api-key"
)

# Read a key out of .env without sourcing it (sourcing executes arbitrary shell,
# and .env values with spaces or '#' would break under `source`).
read_env() {
  local key="$1"
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" .env \
    | head -n1 \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" \
    | tr -d '\r'
}

for pair in "${SECRETS[@]}"; do
  ENV_KEY="${pair%%:*}"
  SECRET_ID="${pair##*:}"
  VALUE="$(read_env "${ENV_KEY}")"

  if [ -z "${VALUE}" ]; then
    echo "⚠ ${ENV_KEY} is empty in .env — skipping (fine for optional keys)"
    continue
  fi

  if ! gcloud secrets describe "${SECRET_ID}" >/dev/null 2>&1; then
    gcloud secrets create "${SECRET_ID}" --replication-policy=automatic >/dev/null
  fi

  printf '%s' "${VALUE}" | gcloud secrets versions add "${SECRET_ID}" --data-file=- >/dev/null
  gcloud secrets add-iam-policy-binding "${SECRET_ID}" \
    --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor" >/dev/null
  echo "✓ ${ENV_KEY} → secret '${SECRET_ID}'"
done

echo
echo "✓ Secrets stored. Next: ./cloudrun/02_build.sh"
