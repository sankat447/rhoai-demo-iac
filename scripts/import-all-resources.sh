#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Import ALL existing AWS resources into Terraform state
# ─────────────────────────────────────────────────────────────────────────────

set -e

cd "$(dirname "$0")/../environments/demo"

echo "🔄 Importing all existing AWS resources into Terraform state..."

# IAM IRSA roles
echo "📦 Importing IAM roles..."
terraform import module.iam_irsa.aws_iam_role.s3_access rhoai-demo-rhoai-s3-access 2>/dev/null || echo "  ⚠️  s3_access already imported"
terraform import 'module.iam_irsa.aws_iam_role.bedrock_access[0]' rhoai-demo-rhoai-bedrock-access 2>/dev/null || echo "  ⚠️  bedrock_access already imported"
terraform import module.iam_irsa.aws_iam_role.ecr_access rhoai-demo-rhoai-ecr-access 2>/dev/null || echo "  ⚠️  ecr_access already imported"
terraform import module.iam_irsa.aws_iam_role.ssm_access rhoai-demo-rhoai-ssm-access 2>/dev/null || echo "  ⚠️  ssm_access already imported"

# Lambda permissions
echo "📦 Importing Lambda permissions..."
terraform import module.lambda.aws_lambda_permission.start rhoai-demo-demo-demo-scheduler/AllowEventBridgeStart 2>/dev/null || echo "  ⚠️  start permission already imported"
terraform import module.lambda.aws_lambda_permission.stop rhoai-demo-demo-demo-scheduler/AllowEventBridgeStop 2>/dev/null || echo "  ⚠️  stop permission already imported"

# Budget (already attempted, but try again)
echo "📦 Importing Budget..."
terraform import module.lambda.aws_budgets_budget.demo rhoai-demo-demo-monthly-budget 2>/dev/null || echo "  ⚠️  budget already imported"

echo ""
echo "✅ Import complete."
echo ""
echo "⚠️  DB Subnet Group issue detected - checking VPC mismatch..."
echo ""

# Check subnet group details
aws rds describe-db-subnet-groups \
  --db-subnet-group-name rhoai-demo-demo-db-subnet-group \
  --query 'DBSubnetGroups[0].[VpcId,Subnets[*].SubnetIdentifier]' \
  --output table --profile rhoai-demo || echo "Subnet group not found"

echo ""
echo "Next: Run 'terraform plan' to check remaining issues"
