#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# redeploy.sh
# Full redeploy from scratch — run after teardown.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "→ Refreshing AWS SSO token..."
aws sts get-caller-identity > /dev/null 2>&1 || { echo "Run: aws-login first"; exit 1; }

echo "→ Refreshing ROSA token..."
rosa login
export RHCS_TOKEN=$(rosa token)

echo "→ Running terraform apply..."
cd "$(dirname "$0")/../environments/demo"
terraform plan -out=tfplan
terraform apply tfplan

echo ""
echo "→ Running post-apply setup (operator roles, ingress, admin user, pgvector)..."
"$(dirname "$0")/post-apply.sh"
