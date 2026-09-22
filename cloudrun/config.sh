#!/usr/bin/env bash
# ==============================================================================
# EDIT THIS FILE FIRST. Every other script sources it.
# ==============================================================================

# Your Google Cloud project ID. Must be globally unique across all of GCP.
# Lowercase letters, digits and hyphens only.
export PROJECT_ID="enterprise-rag-prare"

# Region. asia-south1 = Mumbai Ã¢â‚¬â€ lowest latency from Chennai.
# Keep Qdrant/Neon/Upstash in a nearby region too; every /query makes several
# round trips to them, so cross-continent placement shows up directly in p95.
export REGION="asia-south1"

# Artifact Registry repository that holds the container image.
export REPO="enterprise-rag"
export IMAGE_NAME="enterprise-rag"

# Cloud Run service names.
export API_SERVICE="rag-api"
export UI_SERVICE="rag-ui"

# Runtime service account (created by 00_bootstrap.sh).
export RUNTIME_SA="rag-runtime"

# Derived Ã¢â‚¬â€ do not edit.
export IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE_NAME}"
export RUNTIME_SA_EMAIL="${RUNTIME_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

