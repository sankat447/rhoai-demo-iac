variable "cluster_name"         { type = string; description = "ROSA cluster name prefix for role names" }
variable "aws_region"           { type = string; description = "AWS region" }
variable "oidc_endpoint_url"    { type = string; description = "OIDC endpoint URL from rosa-hcp module output" }
variable "s3_bucket_name"       { type = string; description = "S3 bucket name from s3-data-lake module output" }
variable "enable_bedrock_access" { type = bool; default = true; description = "Create Bedrock invoke role" }
variable "ssm_path_prefix"      { type = string; default = "rhoai-demo"; description = "SSM parameter path prefix" }
variable "tags"                 { type = map(string); default = {} }

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
