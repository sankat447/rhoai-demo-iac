variable "bucket_prefix" {
  description = "S3 bucket name prefix. Account ID appended automatically."
  type        = string
}

variable "create_tfstate_bucket" {
  description = "Also create Terraform remote state bucket + DynamoDB lock table"
  type        = bool
  default     = true
}

variable "pipeline_log_retention_days" {
  description = "Days to retain pipeline log artifacts before expiry"
  type        = number
  default     = 30
}

variable "folder_prefixes" {
  description = "S3 key prefixes to create as placeholder objects (folder structure)"
  type        = list(string)
  default     = [
    "models/",
    "models/archived/",
    "datasets/",
    "datasets/raw/",
    "datasets/processed/",
    "pipelines/",
    "pipelines/logs/",
    "notebooks/"
  ]
}

variable "tags" {
  type    = map(string)
  default = {}
}
