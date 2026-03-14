#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Import existing AWS resources into Terraform state
# ─────────────────────────────────────────────────────────────────────────────

set -e

cd "$(dirname "$0")/../environments/demo"

echo "🔄 Importing existing AWS resources into Terraform state..."

# Aurora resources
terraform import module.aurora.aws_ssm_parameter.db_password /rhoai-demo-demo/aurora/master-password 2>/dev/null || echo "  ⚠️  db_password already in state or doesn't exist"
terraform import module.aurora.aws_rds_cluster_parameter_group.params rhoai-demo-demo-db-params 2>/dev/null || echo "  ⚠️  params already in state or doesn't exist"
terraform import module.aurora.aws_db_subnet_group.this rhoai-demo-demo-db-subnet-group 2>/dev/null || echo "  ⚠️  subnet group already in state or doesn't exist"

# ECR repositories
terraform import 'module.ecr.aws_ecr_repository.repos["rhoai-demo/langchain-server"]' rhoai-demo/langchain-server 2>/dev/null || echo "  ⚠️  langchain-server already in state or doesn't exist"
terraform import 'module.ecr.aws_ecr_repository.repos["rhoai-demo/lambda-metering"]' rhoai-demo/lambda-metering 2>/dev/null || echo "  ⚠️  lambda-metering already in state or doesn't exist"
terraform import 'module.ecr.aws_ecr_repository.repos["rhoai-demo/notebook-base"]' rhoai-demo/notebook-base 2>/dev/null || echo "  ⚠️  notebook-base already in state or doesn't exist"

# EFS
terraform import module.efs.aws_ssm_parameter.efs_id /rhoai-demo-demo/efs/file-system-id 2>/dev/null || echo "  ⚠️  efs_id already in state or doesn't exist"

# Lambda
terraform import module.lambda.aws_iam_role.lambda_exec rhoai-demo-demo-lambda-platform-role 2>/dev/null || echo "  ⚠️  lambda_exec already in state or doesn't exist"
terraform import module.lambda.aws_lambda_function.demo_scheduler rhoai-demo-demo-demo-scheduler 2>/dev/null || echo "  ⚠️  demo_scheduler already in state or doesn't exist"

# Budget
terraform import module.lambda.aws_budgets_budget.demo rhoai-demo-demo-monthly-budget 2>/dev/null || echo "  ⚠️  budget already in state or doesn't exist"

echo "✅ Import complete. Run terraform plan to verify state."
