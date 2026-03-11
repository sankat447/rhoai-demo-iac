# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT: demo — All configurable variables
# Fill values in terraform.tfvars (copy from terraform.tfvars.example)
# ─────────────────────────────────────────────────────────────────────────────

# ── Project Identity ─────────────────────────────────────────────────────────
variable "project_name" {
  description = "Short project name used in resource naming (e.g. 'rhoai-demo')"
  type        = string
  default     = "rhoai-demo"
}

variable "environment" {
  description = "Environment label: demo | staging | prod"
  type        = string
  default     = "demo"
}

variable "owner_tag" {
  description = "Owner name/email for resource tags and cost allocation"
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources. us-east-1 is cheapest for ROSA."
  type        = string
  default     = "us-east-1"
}

# ── Network ──────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "VPC CIDR block. /16 required for ROSA."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy subnets in. 2 for demo, 3 for production HA."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

# ── ROSA Cluster ─────────────────────────────────────────────────────────────
variable "rosa_cluster_name" {
  description = "ROSA cluster name. 4-15 chars, lowercase alphanumeric + hyphens."
  type        = string
  default     = "rhoai-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{4,15}$", var.rosa_cluster_name))
    error_message = "Must be 4-15 chars, lowercase alphanumeric and hyphens."
  }
}

variable "ocp_version" {
  description = "OpenShift version. Check available: rosa list versions --hosted-cp"
  type        = string
  default     = "4.15.28"
}

variable "worker_instance_type" {
  description = "EC2 type for general workers. c5.2xlarge = 8vCPU/16GB RAM."
  type        = string
  default     = "c5.2xlarge"
}

variable "worker_min_replicas" {
  description = "Minimum worker count. 0 = scaled down. 2 = active demo."
  type        = number
  default     = 2
}

variable "worker_max_replicas" {
  description = "Maximum workers (autoscaling ceiling)."
  type        = number
  default     = 4
}

variable "create_gpu_pool" {
  description = "Create GPU machine pool for vLLM. Pool starts at 0 replicas."
  type        = bool
  default     = true
}

variable "gpu_instance_type" {
  description = "GPU instance type. g4dn.xlarge = 4vCPU/16GB T4 GPU."
  type        = string
  default     = "g4dn.xlarge"
}

variable "gpu_max_replicas" {
  description = "Max GPU nodes. Keep at 1 for demo cost control."
  type        = number
  default     = 1
}

# ── Aurora ───────────────────────────────────────────────────────────────────
variable "db_name"                    { type = string; default = "rhoai_demo" }
variable "db_master_username"         { type = string; default = "rhoai_admin" }
variable "aurora_engine_version"      { type = string; default = "15.4" }
variable "aurora_min_acu"             { type = number; default = 0.5;  description = "Min 0.5 ACU = ~$0.06/hr idle" }
variable "aurora_max_acu"             { type = number; default = 4;    description = "Max ACU scales under load" }
variable "aurora_skip_snapshot"       { type = bool;   default = true;  description = "DEMO: true. PROD: false!" }
variable "aurora_deletion_protection" { type = bool;   default = false; description = "DEMO: false. PROD: true!" }
variable "aurora_backup_retention"    { type = number; default = 1;    description = "DEMO: 1 day. PROD: 7+ days." }

# ── S3 ───────────────────────────────────────────────────────────────────────
variable "create_tfstate_bucket"        { type = bool;   default = false; description = "Set true only on first run to bootstrap state backend" }
variable "pipeline_log_retention_days"  { type = number; default = 30 }

# ── ECR ──────────────────────────────────────────────────────────────────────
variable "ecr_repository_names" {
  type    = list(string)
  default = ["rhoai-demo/notebook-base", "rhoai-demo/langchain-server", "rhoai-demo/lambda-metering"]
}
variable "ecr_image_tag_mutability"    { type = string; default = "MUTABLE" }
variable "ecr_scan_on_push"            { type = bool;   default = true }
variable "ecr_enable_quay_pullthrough" { type = bool;   default = false }

# ── Bedrock ──────────────────────────────────────────────────────────────────
variable "enable_bedrock_access" { type = bool; default = true }

# ── Lambda + Automation ──────────────────────────────────────────────────────
variable "budget_alert_email"  { type = string; default = ""; description = "Email for budget alerts" }
variable "monthly_budget_usd"  { type = number; default = 700 }
variable "demo_start_cron"     { type = string; default = "cron(0 8 ? * MON-FRI *)";  description = "UTC time to scale workers UP (8am UTC = adjust for your TZ)" }
variable "demo_stop_cron"      { type = string; default = "cron(0 20 ? * MON-FRI *)"; description = "UTC time to scale workers DOWN" }
