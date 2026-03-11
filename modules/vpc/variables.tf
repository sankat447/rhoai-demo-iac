# ─────────────────────────────────────────────────────────────────────────────
# MODULE: vpc — Input Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "name" {
  description = "Prefix for all resource names (e.g. 'rhoai-demo')"
  type        = string
}

variable "cluster_name" {
  description = "ROSA cluster name — used for required subnet tags"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block. ROSA requires /16 minimum."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of AZs to create subnets in. Demo: 2 AZs. Prod: 3 AZs."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. Must match length of availability_zones."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (ROSA workers live here)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "tags" {
  description = "Tags to apply to all resources in this module."
  type        = map(string)
  default     = {}
}
