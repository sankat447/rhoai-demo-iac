# ─────────────────────────────────────────────────────────────────────────────
# MODULE: rosa-hcp — Input Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "ROSA cluster name. Lowercase alphanumeric and hyphens only. Max 15 chars."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{4,15}$", var.cluster_name))
    error_message = "cluster_name must be 4-15 chars, lowercase alphanumeric and hyphens only."
  }
}

variable "aws_region" {
  description = "AWS region for the ROSA cluster."
  type        = string
  default     = "us-east-1"
}

variable "ocp_version" {
  description = "OpenShift version (without 'openshift-v' prefix). Check: rosa list versions"
  type        = string
  default     = "4.15.28"
}

variable "vpc_cidr" {
  description = "VPC CIDR — must match VPC module output."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from VPC module. ROSA workers deploy here."
  type        = list(string)
}

variable "worker_instance_type" {
  description = "EC2 instance type for general worker nodes."
  type        = string
  default     = "c5.2xlarge"
  # Demo options:
  # c5.2xlarge  — 8 vCPU, 16GB  — good for most workloads (~$0.07/hr spot)
  # m5.2xlarge  — 8 vCPU, 32GB  — more memory for data-heavy workloads
  # c5.4xlarge  — 16 vCPU, 32GB — production sizing
}

variable "worker_min_replicas" {
  description = "Minimum worker replicas. Set to 0 overnight to reduce cost."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_min_replicas >= 0
    error_message = "worker_min_replicas must be 0 or greater."
  }
}

variable "worker_max_replicas" {
  description = "Maximum worker replicas for autoscaling."
  type        = number
  default     = 4
}

variable "create_gpu_pool" {
  description = "Whether to create the GPU machine pool. Set true only when needed."
  type        = bool
  default     = true
}

variable "gpu_instance_type" {
  description = "EC2 instance type for GPU node pool."
  type        = string
  default     = "g4dn.xlarge"
  # Options:
  # g4dn.xlarge  — 4 vCPU, 16GB VRAM T4  — fits 7-8B models (~$0.37/hr spot)
  # g4dn.2xlarge — 8 vCPU, 32GB VRAM T4  — fits 13B models (~$0.75/hr spot)
  # p3.2xlarge   — 8 vCPU, 16GB VRAM V100 — high performance (~$1.00/hr spot)
}

variable "gpu_max_replicas" {
  description = "Maximum GPU node replicas. Keep at 1 for demo to limit cost."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags applied to all ROSA-related resources."
  type        = map(string)
  default     = {}
}
