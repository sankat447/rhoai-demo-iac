variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default = [
    "rhoai-demo/notebook-base",
    "rhoai-demo/langchain-server",
    "rhoai-demo/open-webui-custom",
    "rhoai-demo/lambda-metering"
  ]
}

variable "image_tag_mutability" {
  description = "MUTABLE for demo, IMMUTABLE for production"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  type    = bool
  default = true
}

variable "max_images_to_keep" {
  description = "How many tagged images to retain per repo"
  type        = number
  default     = 10
}

variable "enable_quay_pullthrough" {
  description = "Enable pull-through cache for quay.io"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
