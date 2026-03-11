variable "repository_names" {
  type        = list(string)
  description = "List of ECR repository names to create"
  default = [
    "rhoai-demo/notebook-base",
    "rhoai-demo/langchain-server",
    "rhoai-demo/open-webui-custom",
    "rhoai-demo/lambda-metering"
  ]
}
variable "image_tag_mutability"    { type = string; default = "MUTABLE"; description = "MUTABLE for demo, IMMUTABLE for production" }
variable "scan_on_push"            { type = bool;   default = true }
variable "max_images_to_keep"      { type = number; default = 10; description = "How many tagged images to retain per repo" }
variable "enable_quay_pullthrough" { type = bool;   default = false; description = "Enable pull-through cache for quay.io" }
variable "tags"                    { type = map(string); default = {} }
