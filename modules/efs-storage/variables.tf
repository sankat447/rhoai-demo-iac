variable "name"             { type = string; description = "Resource name prefix" }
variable "vpc_id"           { type = string }
variable "vpc_cidr"         { type = string }
variable "subnet_ids"       { type = list(string); description = "Private subnets for EFS mount targets" }
variable "performance_mode" { type = string; default = "generalPurpose" }
variable "throughput_mode"  { type = string; default = "bursting" }
variable "ssm_path_prefix"  { type = string; default = "rhoai-demo" }
variable "tags"             { type = map(string); default = {} }
