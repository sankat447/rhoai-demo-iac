#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# provision.sh — Full demo stack creation (~25-30 minutes)
# Usage: aws-vault exec rhoai-demo -- ./scripts/provision.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/../environments/demo"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "🚀 Starting RHOAI Demo Environment Provisioning"

# Verify prerequisites
command -v terraform >/dev/null || { echo "❌ terraform not found. Run: tfenv install 1.8.5"; exit 1; }
command -v rosa      >/dev/null || { echo "❌ rosa CLI not found. Run: brew install rosa-cli"; exit 1; }
command -v oc        >/dev/null || { echo "❌ oc CLI not found. Run: brew install openshift-cli"; exit 1; }

# Check AWS credentials
aws sts get-caller-identity --query "Account" --output text >/dev/null || { echo "❌ AWS credentials not set. Use aws-vault exec rhoai-demo --"; exit 1; }

# RHCS token required for ROSA provider
[ -z "${RHCS_TOKEN:-}" ] && { echo "❌ RHCS_TOKEN not set. Run: export RHCS_TOKEN=\$(cat ~/rh-ocm-token.json)"; exit 1; }

log "✅ Prerequisites OK"

# Terraform apply
cd "${ENV_DIR}"
log "📦 Running terraform init..."
terraform init -input=false

log "📋 Running terraform plan..."
terraform plan -out=tfplan -input=false

log "🏗️  Applying infrastructure (~25 min for ROSA cluster creation)..."
terraform apply tfplan

log "✅ Terraform apply complete"

# Post-apply: login to ROSA
ROSA_API_URL=$(terraform output -raw rosa_api_url 2>/dev/null || echo "")
if [ -n "${ROSA_API_URL}" ]; then
  log "🔴 Logging into ROSA cluster..."
  rosa login --token="${RHCS_TOKEN}"
  log "Run: oc login --server=${ROSA_API_URL} --username=cluster-admin"
fi

# Show next steps
terraform output next_steps

log "🎉 Provisioning complete!"
