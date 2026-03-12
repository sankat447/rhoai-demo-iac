variable "name" {
  description = "Resource name prefix"
  type        = string
}

variable "rosa_cluster_name" {
  description = "ROSA cluster name for scheduler"
  type        = string
}

variable "ssm_path_prefix" {
  type    = string
  default = "rhoai-demo"
}

variable "alert_email" {
  description = "Email for budget alerts. Leave empty to skip."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly AWS budget in USD before alert fires"
  type        = number
  default     = 700
}

variable "start_schedule_cron" {
  description = "EventBridge cron to scale workers UP (UTC)"
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"
}

variable "stop_schedule_cron" {
  description = "EventBridge cron to scale workers DOWN (UTC)"
  type        = string
  default     = "cron(0 20 ? * MON-FRI *)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
