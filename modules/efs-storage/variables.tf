variable "name" {
  description = "Resource name prefix"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for EFS mount targets"
  type        = list(string)
}

variable "performance_mode" {
  type    = string
  default = "generalPurpose"
}

variable "throughput_mode" {
  type    = string
  default = "bursting"
}

variable "ssm_path_prefix" {
  type    = string
  default = "rhoai-demo"
}

variable "tags" {
  type    = map(string)
  default = {}
}
