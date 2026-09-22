#!/usr/bin/env bash
# ==============================================================================
# STEP 0 — One-time project bootstrap.
#
# Creates the project, enables the four APIs this deployment touches, creates
# the image repository, and creates a least-privilege runtime identity.
#
# Idempotent: safe to re-run. Every create is guarded by an existence check.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source cloudrun/config.sh

echo "▶ Project: ${PROJECT_ID}   Region: ${REGION}"

# --- 1. Project ---------------------------------------------------------------
# A project is GCP's billing and IAM boundary. Everything below lives inside it,
# which is also what makes teardown a single delete at the end.
if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  echo "▶ Creating project ${PROJECT_ID}"
  gcloud projects create "${PROJECT_ID}"
else
  echo "✓ Project already exists"
fi
gcloud config set project "${PROJECT_ID}"

# --- 2. Billing ---------------------------------------------------------------
# Cloud Run will not deploy without a billing account linked, even though the
# free tier means you are very unlikely to be charged.
BILLING_ACCOUNT="$(gcloud billing accounts list --format='value(name)' --limit=1)"
if [ -z "${BILLING_ACCOUNT}" ]; then
  echo "✗ No billing account found. Create one at console.cloud.google.com/billing"
  echo "  New accounts receive \$300 in credit. Then re-run this script."
  exit 1
fi
gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"
echo "✓ Billing linked: ${BILLING_ACCOUNT}"

# --- 3. APIs ------------------------------------------------------------------
#   run              — the serverless container runtime itself
#   cloudbuild       — builds the image (so you need no local Docker)
#   artifactregistry — stores the built image
#   secretmanager    — holds the API keys; the GCP analogue of AWS Secrets Manager
echo "▶ Enabling APIs (takes ~60s the first time)"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com

# --- 4. Artifact Registry -----------------------------------------------------
if ! gcloud artifacts repositories describe "${REPO}" --location="${REGION}" >/dev/null 2>&1; then
  echo "▶ Creating Artifact Registry repo ${REPO}"
  gcloud artifacts repositories create "${REPO}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Enterprise Agentic RAG container images"
else
  echo "✓ Artifact Registry repo already exists"
fi

# --- 5. Runtime service account -----------------------------------------------
# Cloud Run's default service account is the Compute Engine default, which is
# broadly over-privileged. A dedicated identity that can read secrets and do
# nothing else is the whole of least privilege here, and it is the kind of
# detail an interviewer will notice.
if ! gcloud iam service-accounts describe "${RUNTIME_SA_EMAIL}" >/dev/null 2>&1; then
  echo "▶ Creating runtime service account ${RUNTIME_SA}"
  gcloud iam service-accounts create "${RUNTIME_SA}" \
    --display-name="Enterprise RAG Cloud Run runtime"
else
  echo "✓ Runtime service account already exists"
fi

echo
echo "✓ Bootstrap complete. Next: ./cloudrun/01_secrets.sh"
