# ─────────────────────────────────────────────────────────────────────────────
# MODULE: iam-irsa — Input Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "ROSA cluster name prefix for role names"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "oidc_endpoint_url" {
  description = "OIDC endpoint URL from rosa-hcp module output"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name from s3-data-lake module output"
  type        = string
}

variable "enable_bedrock_access" {
  description = "Create Bedrock invoke role"
  type        = bool
  default     = true
}

variable "ssm_path_prefix" {
  description = "SSM parameter path prefix"
  type        = string
  default     = "rhoai-demo"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "service_account_roles" {
  description = "Map of SA bindings. Key = role name, value = {namespace, service_account}."
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default = {
    s3      = { namespace = "rhoai",     service_account = "*" }
    bedrock = { namespace = "langchain", service_account = "*" }
    ecr     = { namespace = "rhoai",     service_account = "*" }
    ssm     = { namespace = "rhoai",     service_account = "*" }
  }
}
