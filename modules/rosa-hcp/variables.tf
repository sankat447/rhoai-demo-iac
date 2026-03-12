# ─────────────────────────────────────────────────────────────────────────────
# MODULE: rosa-hcp — Variables (rhcs v1.7 verified schema)
# ─────────────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "ROSA cluster name. 4-15 chars, lowercase alphanumeric + hyphens."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{4,15}$", var.cluster_name))
    error_message = "Must be 4-15 chars, lowercase alphanumeric and hyphens only."
  }
}

variable "aws_region" {
  description = "AWS region for the ROSA cluster."
  type        = string
  default     = "us-east-1"
}

variable "ocp_version" {
  description = "OpenShift version without 'openshift-v' prefix. Check: rosa list versions --hosted-cp"
  type        = string
  default     = "4.16.21"
}

variable "vpc_cidr" {
  description = "VPC CIDR — must match VPC module output."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from VPC module."
  type        = list(string)
}

variable "availability_zones" {
  description = "AZs matching the private subnets. Required by rhcs_cluster_rosa_hcp."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "oidc_config_id" {
  description = <<-DESC
    OIDC config ID. Create with:
      rosa create oidc-config --managed --yes --region us-east-1
      rosa list oidc-config   (copy the ID column)
  DESC
  type        = string
}

variable "account_role_prefix" {
  description = <<-DESC
    Prefix used when creating account roles. Create with:
      rosa create account-roles --hosted-cp --prefix rhoai-demo --yes
  DESC
  type        = string
  default     = "rhoai-demo"
}

variable "worker_instance_type" {
  description = "EC2 instance type for general worker nodes."
  type        = string
  default     = "c5.2xlarge"
}

variable "worker_min_replicas" {
  description = "Min worker replicas. 0 = scaled down overnight."
  type        = number
  default     = 2
  validation {
    condition     = var.worker_min_replicas >= 0
    error_message = "Must be 0 or greater."
  }
}

variable "worker_max_replicas" {
  description = "Max worker replicas for autoscaling."
  type        = number
  default     = 4
}

variable "create_gpu_pool" {
  description = "Create GPU machine pool (starts at 0 replicas)."
  type        = bool
  default     = true
}

variable "gpu_instance_type" {
  description = "GPU instance type. g4dn.xlarge = 16GB T4."
  type        = string
  default     = "g4dn.xlarge"
}

variable "gpu_max_replicas" {
  description = "Max GPU nodes. Keep 1 for demo."
  type        = number
  default     = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from VPC module — required for public NLB ingress."
  type        = list(string)
  default     = []
}

variable "private" {
  description = "Set true for private cluster (no public API/console). False for demo access."
  type        = bool
  default     = false
}
