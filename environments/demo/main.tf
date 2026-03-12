# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT: demo
# Wires together all platform modules for the RHOAI demo environment.
#
# PLATFORM SCOPE (this file):
#   VPC → S3 → Aurora → EFS → ECR → Lambda
#   ROSA + IAM/IRSA → enabled once IAM CreateRole permission is granted
#
# APPLICATION SCOPE (separate GitOps repo):
#   RHOAI operator, ArgoCD bootstrap, Helm charts for Open WebUI / n8n /
#   LangChain / Redis / MongoDB — deployed AFTER this Terraform completes.
#
# Deployment order:
#   Phase 1 (now)   : VPC, S3, Aurora, EFS, ECR, Lambda
#   Phase 2 (later) : Uncomment ROSA + IAM_IRSA modules once IAM perms granted
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name   = "${var.project_name}-${var.environment}"
  region = var.aws_region
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE 1: VPC + Networking
# ─────────────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  name         = local.name
  cluster_name = var.rosa_cluster_name

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE 2: S3 — Data lake + Terraform state bucket
# ─────────────────────────────────────────────────────────────────────────────
module "s3" {
  source = "../../modules/s3-data-lake"

  bucket_prefix               = local.name
  create_tfstate_bucket       = var.create_tfstate_bucket
  pipeline_log_retention_days = var.pipeline_log_retention_days

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE 3: ROSA HCP Cluster
# ─────────────────────────────────────────────────────────────────────────────
# BLOCKED: Waiting for iam:CreateRole permission on SystemAdministrator role.
# Once granted, run:
#   rosa create account-roles --hosted-cp --prefix rhoai-demo --yes
#   rosa create oidc-config --managed --yes
# Then uncomment this block and add oidc_config_id to terraform.tfvars
# ─────────────────────────────────────────────────────────────────────────────
module "rosa" {
  source = "../../modules/rosa-hcp"
  cluster_name         = var.rosa_cluster_name
  aws_region           = var.aws_region
  ocp_version          = var.ocp_version
  vpc_cidr             = var.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  public_subnet_ids    = module.vpc.public_subnet_ids
  private              = false
  availability_zones   = var.availability_zones
  oidc_config_id       = var.oidc_config_id
  account_role_prefix  = var.account_role_prefix
  worker_instance_type = var.worker_instance_type
  worker_min_replicas  = var.worker_min_replicas
  worker_max_replicas  = var.worker_max_replicas
  create_gpu_pool      = var.create_gpu_pool
  gpu_instance_type    = var.gpu_instance_type
  gpu_max_replicas     = var.gpu_max_replicas
  tags       = local.tags
  depends_on = [module.vpc]
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE 4: IAM / IRSA
# ─────────────────────────────────────────────────────────────────────────────
# BLOCKED: Depends on module.rosa OIDC endpoint. Uncomment with ROSA above.
# ─────────────────────────────────────────────────────────────────────────────
module "iam_irsa" {
  source = "../../modules/iam-irsa"

  cluster_name          = var.rosa_cluster_name
  aws_region            = var.aws_region
  oidc_endpoint_url     = module.rosa.oidc_endpoint_url
  s3_bucket_name        = module.s3.bucket_name
  enable_bedrock_access = var.enable_bedrock_access
  ssm_path_prefix       = local.name

  tags       = local.tags
  depends_on = [module.rosa, module.s3]
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE 5: Aurora Serverless v2 + pgvector
# ─────────────────────────────────────────────────────────────────────────────
module "aurora" {
  source = "../../modules/aurora-serverless"

  cluster_identifier    = "${local.name}-db"
  database_name         = var.db_name
  master_username       = var.db_master_username
  engine_version        = var.aurora_engine_version
  min_acu               = var.aurora_min_acu
  max_acu               = var.aurora_max_acu
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  subnet_ids            = module.vpc.private_subnet_ids
  ssm_path_prefix       = local.name
  skip_final_snapshot   = var.aurora_skip_snapshot
  deletion_protection   = var.aurora_deletion_protection
  backup_retention_days = var.aurora_backup_retention

  tags       = local.tags
  depends_on = [module.vpc]
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE 6: EFS Storage — RWX PVCs for RHOAI Jupyter notebooks
# ─────────────────────────────────────────────────────────────────────────────
module "efs" {
  source = "../../modules/efs-storage"

  name            = local.name
  vpc_id          = module.vpc.vpc_id
  vpc_cidr        = module.vpc.vpc_cidr
  subnet_ids      = module.vpc.private_subnet_ids
  ssm_path_prefix = local.name

  tags       = local.tags
  depends_on = [module.vpc]
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE 7: ECR Repositories — Container image registry
# ─────────────────────────────────────────────────────────────────────────────
module "ecr" {
  source = "../../modules/ecr-repos"

  repository_names        = var.ecr_repository_names
  image_tag_mutability    = var.ecr_image_tag_mutability
  scan_on_push            = var.ecr_scan_on_push
  enable_quay_pullthrough = var.ecr_enable_quay_pullthrough

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE 8: Lambda — Platform automation (scheduler, budget alerts)
# Note: depends_on rosa removed — scheduler still works, just targets cluster
#       by name rather than ID.
# ─────────────────────────────────────────────────────────────────────────────
module "lambda" {
  source = "../../modules/lambda-triggers"

  name               = local.name
  rosa_cluster_name  = var.rosa_cluster_name
  ssm_path_prefix    = local.name
  alert_email        = var.budget_alert_email
  monthly_budget_usd = var.monthly_budget_usd
  start_schedule_cron = var.demo_start_cron
  stop_schedule_cron  = var.demo_stop_cron

  tags = local.tags
}
