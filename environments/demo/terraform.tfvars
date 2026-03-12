# ─────────────────────────────────────────────────────────────────────────────
# terraform.tfvars.example
#
# HOW TO USE:
#   cp terraform.tfvars.example terraform.tfvars
#   Edit terraform.tfvars with your values
#   terraform.tfvars is in .gitignore — NEVER commit it
#
# SENSITIVE values (OCM token, passwords):
#   Store in AWS SSM Parameter Store or environment variables.
#   Never put real secrets in this file.
# ─────────────────────────────────────────────────────────────────────────────

# ── Project Identity — FILL THESE IN ────────────────────────────────────────
project_name = "rhoai-demo"
environment  = "demo"
owner_tag    = "skumar@iisl.com"           # e.g. "john.smith@company.com"
aws_region   = "us-east-1"                    # cheapest for ROSA

# ── Network ──────────────────────────────────────────────────────────────────
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
private_subnet_cidrs = ["10.0.1.0/24",   "10.0.2.0/24"]

# ── ROSA Cluster ─────────────────────────────────────────────────────────────
rosa_cluster_name    = "rhoai-demo"           # Max 15 chars, lowercase + hyphens
ocp_version          = "4.17.50"              # Run: rosa list versions --hosted-cp

# Worker nodes
worker_instance_type = "c5.2xlarge"           # 8vCPU, 16GB RAM — demo default
worker_min_replicas  = 2                      # 0 = scaled down, 2 = active
worker_max_replicas  = 4

# GPU pool for vLLM (starts at 0 — only costs when scaled up)
create_gpu_pool      = true
gpu_instance_type    = "g4dn.xlarge"          # 16GB T4 — fits 7-8B models
gpu_max_replicas     = 1

# ── Aurora PostgreSQL (Serverless v2 + pgvector) ─────────────────────────────
db_name                    = "rhoai_demo"
db_master_username         = "rhoai_admin"    # Password auto-generated, stored in SSM
aurora_engine_version      = "16.4"
aurora_min_acu             = 0.5              # Cheapest idle = ~$0.06/hr
aurora_max_acu             = 4
aurora_skip_snapshot       = true             # CHANGE TO false FOR PRODUCTION
aurora_deletion_protection = false            # CHANGE TO true FOR PRODUCTION
aurora_backup_retention    = 1                # CHANGE TO 7 FOR PRODUCTION

# ── S3 Data Lake ─────────────────────────────────────────────────────────────
create_tfstate_bucket       = false           # true only on very first bootstrap run
pipeline_log_retention_days = 30

# ── ECR ──────────────────────────────────────────────────────────────────────
ecr_repository_names = [
  "rhoai-demo/notebook-base",
  "rhoai-demo/langchain-server",
  "rhoai-demo/lambda-metering"
]
ecr_image_tag_mutability    = "MUTABLE"       # IMMUTABLE for production
ecr_scan_on_push            = true
ecr_enable_quay_pullthrough = false

# ── Bedrock ──────────────────────────────────────────────────────────────────
enable_bedrock_access = true

# ── Cost Control ─────────────────────────────────────────────────────────────
budget_alert_email  = "Yskumar@iisl.com" # Get alerted before bill spikes
monthly_budget_usd  = 700

# Demo auto-scheduler (scale workers up/down on weekdays)
# Times are UTC — adjust for your timezone:
#   UTC 8am  = 4am US East, 9am UK, 1pm India (IST)
#   UTC 20pm = 4pm US East, 9pm UK, 1:30am India (next day)
demo_start_cron = "cron(0 8 ? * MON-FRI *)"
demo_stop_cron  = "cron(0 20 ? * MON-FRI *)"

oidc_config_id      = "2ovm1pcngkss9e6stmbirbefljiiuptk"
account_role_prefix = "rhoai-demo"
