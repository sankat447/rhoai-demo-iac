#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# cleanup.sh
# Full teardown of Phase 1 demo environment
# WARNING: Destroys ALL resources including Aurora data and S3 objects
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

echo "⚠️  WARNING: This will DESTROY all Phase 1 resources!"
echo "   Account: ${ACCOUNT_ID}"
echo "   Region:  ${REGION}"
echo ""
read -p "Type 'destroy' to confirm: " CONFIRM
if [[ "${CONFIRM}" != "destroy" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "🧹 Starting cleanup..."

# ── Step 1: Terraform destroy ─────────────────────────────────────────────────
echo "→ Running terraform destroy..."
cd "$(dirname "$0")/../environments/demo"
terraform destroy -auto-approve

# ── Step 2: Clean up Secrets Manager secret ───────────────────────────────────
echo "→ Deleting Secrets Manager secret..."
aws secretsmanager delete-secret \
  --secret-id "rhoai-demo/aurora-master" \
  --force-delete-without-recovery \
  --region "${REGION}" 2>/dev/null && echo "  ✅ Secret deleted" || echo "  ℹ️  Secret not found"

# ── Step 3: Empty and delete S3 data lake bucket ─────────────────────────────
BUCKET="rhoai-demo-demo-${ACCOUNT_ID}"
echo "→ Emptying S3 bucket ${BUCKET}..."
aws s3 rm "s3://${BUCKET}" --recursive 2>/dev/null && \
  echo "  ✅ S3 bucket emptied" || echo "  ℹ️  Bucket not found or already empty"

# ── Step 4: Clean up any leftover EC2 bastions ───────────────────────────────
echo "→ Terminating any rhoai-demo-bastion instances..."
BASTION_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=rhoai-demo-bastion" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)
if [[ -n "${BASTION_IDS}" ]]; then
  aws ec2 terminate-instances --instance-ids ${BASTION_IDS}
  echo "  ✅ Bastions terminated: ${BASTION_IDS}"
else
  echo "  ℹ️  No bastion instances found"
fi

# ── Step 5: Optional - delete OIDC config (keep if reusing) ──────────────────
echo ""
echo "─────────────────────────────────────────────────────────────────────────"
echo "ℹ️  OIDC config and account roles were NOT deleted."
echo "   Keep them if you plan to recreate the cluster."
echo "   To delete:"
echo "   rosa delete oidc-config --id 2ovm1pcngkss9e6stmbirbefljiiuptk --yes"
echo "   rosa delete account-roles --prefix rhoai-demo --yes"
echo ""
echo "✅ Phase 1 cleanup complete!"
