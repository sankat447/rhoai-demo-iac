variable "name"                  { type = string; description = "Resource name prefix" }
variable "rosa_cluster_name"     { type = string; description = "ROSA cluster name for scheduler" }
variable "ssm_path_prefix"       { type = string; default = "rhoai-demo" }
variable "alert_email"           { type = string; default = ""; description = "Email for budget alerts. Leave empty to skip." }
variable "monthly_budget_usd"    { type = number; default = 700; description = "Monthly AWS budget in USD before alert fires" }
variable "start_schedule_cron"   { type = string; default = "cron(0 8 ? * MON-FRI *)"; description = "EventBridge cron to scale workers UP (UTC)" }
variable "stop_schedule_cron"    { type = string; default = "cron(0 20 ? * MON-FRI *)"; description = "EventBridge cron to scale workers DOWN (UTC)" }
variable "tags"                  { type = map(string); default = {} }
