#!/usr/bin/env bash
# ==============================================================================
# STEP 5 (optional) — Wire GitHub Actions to Cloud Run via Workload Identity
# Federation, so CI/CD deploys WITHOUT a long-lived service-account JSON key.
#
# Why this matters: the existing AWS workflow (.github/workflows/cd.yml) uses
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY — static credentials sitting in
# GitHub secrets forever. WIF instead lets GitHub mint a short-lived token that
# GCP trusts because of who is asking (this repo, this branch), not because of a
# shared secret. If an interviewer asks "how do you handle CI credentials",
# this is the answer you want to give.
#
# Usage:  ./cloudrun/05_github_wif.sh <github-user>/<repo-name>
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source cloudrun/config.sh

GITHUB_REPO="${1:-}"
if [ -z "${GITHUB_REPO}" ]; then
  echo "Usage: $0 <github-user>/<repo-name>"
  exit 1
fi

POOL="github-pool"
PROVIDER="github-provider"
DEPLOY_SA="rag-deployer"
DEPLOY_SA_EMAIL="${DEPLOY_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"

gcloud services enable iamcredentials.googleapis.com sts.googleapis.com

# --- Deployer identity: can build, push and deploy. Nothing else. -------------
if ! gcloud iam service-accounts describe "${DEPLOY_SA_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${DEPLOY_SA}" --display-name="GitHub Actions deployer"
fi
for role in roles/run.admin roles/cloudbuild.builds.editor \
            roles/artifactregistry.writer roles/storage.admin \
            roles/iam.serviceAccountUser roles/logging.viewer; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${DEPLOY_SA_EMAIL}" --role="${role}" >/dev/null
done

# --- Identity pool that trusts GitHub's OIDC issuer ---------------------------
if ! gcloud iam workload-identity-pools describe "${POOL}" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "${POOL}" \
    --location=global --display-name="GitHub Actions pool"
fi

if ! gcloud iam workload-identity-pools providers describe "${PROVIDER}" \
      --location=global --workload-identity-pool="${POOL}" >/dev/null 2>&1; then
  # attribute-condition is the security boundary. Without it, ANY GitHub repo on
  # the internet could assume this identity. Scoping to your repository owner is
  # mandatory, not optional.
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER}" \
    --location=global \
    --workload-identity-pool="${POOL}" \
    --display-name="GitHub OIDC" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository=='${GITHUB_REPO}'"
fi

# --- Let only this repo impersonate the deployer ------------------------------
gcloud iam service-accounts add-iam-policy-binding "${DEPLOY_SA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${GITHUB_REPO}"

PROVIDER_PATH="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"

cat <<SUMMARY

✓ Workload Identity Federation configured.

Add these as GitHub repository secrets
(Settings → Secrets and variables → Actions → New repository secret):

  GCP_PROJECT_ID           ${PROJECT_ID}
  GCP_REGION               ${REGION}
  GCP_WIF_PROVIDER         ${PROVIDER_PATH}
  GCP_DEPLOY_SA            ${DEPLOY_SA_EMAIL}

No JSON key is created, and none should ever be.
SUMMARY
