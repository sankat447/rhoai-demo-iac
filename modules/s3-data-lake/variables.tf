variable "bucket_prefix"               { type = string; description = "S3 bucket name prefix. Account ID appended automatically." }
variable "create_tfstate_bucket"        { type = bool;   default = true; description = "Also create Terraform remote state bucket + DynamoDB lock table" }
variable "pipeline_log_retention_days" { type = number; default = 30;   description = "Days to retain pipeline log artifacts before expiry" }
variable "folder_prefixes" {
  type    = list(string)
  default = ["models/", "models/archived/", "datasets/", "datasets/raw/", "datasets/processed/", "pipelines/", "pipelines/logs/", "notebooks/"]
  description = "S3 key prefixes to create as placeholder objects (folder structure)"
}
variable "tags" { type = map(string); default = {} }
