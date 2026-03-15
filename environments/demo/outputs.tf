# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT: demo — Key Outputs
# ROSA + IAM outputs commented out until IAM permissions are granted
# ─────────────────────────────────────────────────────────────────────────────

# ── VPC ──────────────────────────────────────────────────────────────────────
output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnet_ids
  description = "Private subnet IDs"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnet_ids
  description = "Public subnet IDs"
}

output "nat_gateway_ip" {
  value       = module.vpc.nat_gateway_ip
  description = "NAT Gateway EIP — whitelist in external systems if needed"
}

# ── S3 ───────────────────────────────────────────────────────────────────────
output "s3_bucket_name" {
  value       = module.s3.bucket_name
  description = "Main data lake bucket name"
}

output "s3_bucket_arn" {
  value       = module.s3.bucket_arn
  description = "Main data lake bucket ARN"
}

# ── Aurora ───────────────────────────────────────────────────────────────────
output "aurora_endpoint" {
  value       = module.aurora.cluster_endpoint
  description = "Aurora writer endpoint"
}

output "aurora_database_name" {
  value       = module.aurora.database_name
  description = "Database name"
}

output "aurora_port" {
  value       = module.aurora.port
  description = "Database port"
}

output "aurora_ssm_password_path" {
  value       = module.aurora.ssm_password_path
  description = "SSM path for DB password — retrieve with: aws ssm get-parameter --name THIS --with-decryption"
}

output "aurora_ssm_endpoint_path" {
  value       = module.aurora.ssm_endpoint_path
  description = "SSM path for DB endpoint"
}

# ── EFS ──────────────────────────────────────────────────────────────────────
output "efs_file_system_id" {
  value       = module.efs.file_system_id
  description = "EFS file system ID — use in AWS EFS CSI StorageClass on ROSA"
}

output "efs_access_point_id" {
  value       = module.efs.access_point_id
  description = "EFS access point ID for RHOAI namespace"
}

# ── ECR ──────────────────────────────────────────────────────────────────────
output "ecr_repository_urls" {
  value       = module.ecr.repository_urls
  description = "Map of ECR repo name to URL — use in docker push commands"
}

output "ecr_registry_id" {
  value       = module.ecr.registry_id
  description = "ECR registry ID (AWS account ID)"
}

# ── Lambda / Budget ──────────────────────────────────────────────────────────
output "budget_name" {
  value       = module.lambda.budget_name
  description = "AWS Budget name — view in AWS Cost Management console"
}

output "scheduler_lambda_arn" {
  value       = module.lambda.scheduler_lambda_arn
  description = "Demo scheduler Lambda ARN"
}

# ── ROSA + IAM ──────────────────────────────────────────────────────────────
output "rosa_cluster_id" {
  value       = module.rosa.cluster_id
  description = "ROSA cluster ID"
}

output "rosa_api_url" {
  value       = module.rosa.api_url
  description = "ROSA API URL"
}

output "rosa_console_url" {
  value       = module.rosa.console_url
  description = "ROSA console URL"
}

output "oidc_endpoint_url" {
  value       = module.rosa.oidc_endpoint_url
  description = "OIDC endpoint URL"
}

output "bedrock_role_arn" {
  value       = module.iam_irsa.bedrock_role_arn
  description = "Bedrock IRSA role ARN"
}

output "s3_role_arn" {
  value       = module.iam_irsa.s3_role_arn
  description = "S3 IRSA role ARN"
}

output "ecr_role_arn" {
  value       = module.iam_irsa.ecr_role_arn
  description = "ECR IRSA role ARN"
}

output "ssm_role_arn" {
  value       = module.iam_irsa.ssm_role_arn
  description = "SSM IRSA role ARN"
}

# ── Next Steps ────────────────────────────────────────────────────────────────
output "next_steps" {
  description = "What to do after terraform apply"
  value = <<-STEPS

  ── PHASE 1 COMPLETE — Platform Layer (non-ROSA) ─────────────────────────────
  ✅ VPC: ${module.vpc.vpc_id}
  ✅ S3 bucket: ${module.s3.bucket_name}
  ✅ Aurora endpoint: ${module.aurora.cluster_endpoint}
  ✅ EFS: ${module.efs.file_system_id}

  ── NEXT: Get DB password ────────────────────────────────────────────────────
  aws ssm get-parameter \
    --name ${module.aurora.ssm_password_path} \
    --with-decryption --query Parameter.Value --output text

  ── NEXT: Initialise pgvector in Aurora ──────────────────────────────────────
  DB_PASS=$(aws ssm get-parameter --name ${module.aurora.ssm_password_path} --with-decryption --query Parameter.Value --output text)
  psql "postgresql://rhoai_admin:$DB_PASS@${module.aurora.cluster_endpoint}/rhoai_demo" \
    -f ../../modules/aurora-serverless/init.sql

  ── PHASE 2 PENDING — ROSA cluster ───────────────────────────────────────────
  1. Get iam:CreateRole added to SystemAdministrator SSO permission set
  2. Run: rosa create account-roles --hosted-cp --prefix rhoai-demo --yes
  3. Run: rosa create oidc-config --managed --yes
  4. Add oidc_config_id to terraform.tfvars
  5. Uncomment module "rosa" and module "iam_irsa" in main.tf
  6. Run: terraform apply
  ─────────────────────────────────────────────────────────────────────────────
  STEPS
}
