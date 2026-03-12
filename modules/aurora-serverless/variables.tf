variable "cluster_identifier" {
  description = "Aurora cluster identifier (e.g. 'rhoai-demo-db')"
  type        = string
}

variable "database_name" {
  description = "Initial database name"
  type        = string
  default     = "rhoai_demo"
}

variable "master_username" {
  description = "Master DB username"
  type        = string
  default     = "rhoai_admin"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "min_acu" {
  description = "Min ACU (0.5 = cheapest idle cost ~$0.06/hr)"
  type        = number
  default     = 0.5
}

variable "max_acu" {
  description = "Max ACU under load"
  type        = number
  default     = 4
}

variable "vpc_id" {
  description = "VPC ID from vpc module"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR for SG ingress rule"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for DB subnet group"
  type        = list(string)
}

variable "ssm_path_prefix" {
  description = "SSM parameter path prefix"
  type        = string
  default     = "rhoai-demo"
}

variable "skip_final_snapshot" {
  description = "true for demo, false for production!"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "true for production!"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention. 1 for demo, 7+ for prod."
  type        = number
  default     = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
