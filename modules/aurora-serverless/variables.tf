variable "cluster_identifier"   { type = string; description = "Aurora cluster identifier (e.g. 'rhoai-demo-db')" }
variable "database_name"        { type = string; default = "rhoai_demo"; description = "Initial database name" }
variable "master_username"      { type = string; default = "rhoai_admin"; description = "Master DB username" }
variable "engine_version"       { type = string; default = "15.4"; description = "PostgreSQL engine version" }
variable "min_acu"              { type = number; default = 0.5; description = "Min ACU (0.5 = cheapest idle cost ~$0.06/hr)" }
variable "max_acu"              { type = number; default = 4;   description = "Max ACU under load" }
variable "vpc_id"               { type = string; description = "VPC ID from vpc module" }
variable "vpc_cidr"             { type = string; description = "VPC CIDR for SG ingress rule" }
variable "subnet_ids"           { type = list(string); description = "Private subnet IDs for DB subnet group" }
variable "ssm_path_prefix"      { type = string; default = "rhoai-demo"; description = "SSM parameter path prefix" }
variable "skip_final_snapshot"  { type = bool; default = true;  description = "true for demo, false for production!" }
variable "deletion_protection"  { type = bool; default = false; description = "true for production!" }
variable "backup_retention_days" { type = number; default = 1;  description = "Backup retention. 1 for demo, 7+ for prod." }
variable "tags"                 { type = map(string); default = {} }
