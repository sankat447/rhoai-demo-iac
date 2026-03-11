#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# teardown.sh — Destroy everything (use when not needed for days/weeks)
# Usage: aws-vault exec rhoai-demo -- ./scripts/teardown.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/../environments/demo"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

echo ""
echo "⚠️  WARNING: This will DESTROY all demo resources including:"
echo "   - ROSA HCP cluster (all namespaces and workloads)"
echo "   - Aurora PostgreSQL cluster (all data)"
echo "   - EFS file system (all notebook files)"
echo "   - VPC, subnets, NAT gateway"
echo "   - IAM roles (IRSA)"
echo ""
echo "   S3 bucket and ECR images are NOT deleted (manual cleanup)."
echo ""
read -rp "Type 'destroy-demo' to confirm: " confirm
[ "${confirm}" != "destroy-demo" ] && { echo "Aborted."; exit 1; }

log "🗑️  Starting teardown..."

# Scale down machine pools first (faster cluster deletion)
CLUSTER_NAME=$(cd "${ENV_DIR}" && terraform output -raw rosa_cluster_name 2>/dev/null || echo "rhoai-demo")
log "Scaling workers to 0 before cluster deletion..."
rosa edit machinepool workers --cluster="${CLUSTER_NAME}" --replicas=0 2>/dev/null || true
rosa edit machinepool gpu-demo --cluster="${CLUSTER_NAME}" --replicas=0 2>/dev/null || true

cd "${ENV_DIR}"
log "💥 Running terraform destroy..."
terraform destroy -auto-approve

log "🧹 Cleaning up ROSA account roles..."
rosa delete account-roles --prefix "${CLUSTER_NAME}" --yes 2>/dev/null || true

log "✅ Teardown complete. Billing should drop to ~\$0/hr"
log "   Note: S3 tfstate bucket preserved for next provision run."
