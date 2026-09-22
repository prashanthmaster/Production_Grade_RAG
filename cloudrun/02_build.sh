#!/usr/bin/env bash
# ==============================================================================
# STEP 2 — Build the image with Cloud Build. No local Docker required.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source cloudrun/config.sh

# SHORT_SHA is auto-populated when Cloud Build is triggered by a git push. For a
# manual submit we supply it ourselves so images stay traceable to a commit.
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo manual-$(date +%Y%m%d-%H%M%S))"

echo "▶ Building ${IMAGE}:${SHA}"
echo "  (first build ~5 min: it installs deps and bakes the guardrails model)"

gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions="_IMAGE=${IMAGE},SHORT_SHA=${SHA}" \
  .

echo
echo "✓ Image pushed: ${IMAGE}:${SHA}"
echo "  Next: ./cloudrun/03_deploy_api.sh"
