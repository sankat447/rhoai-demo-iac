output "scheduler_lambda_arn"    { value = aws_lambda_function.demo_scheduler.arn }
output "budget_alert_topic_arn"  { value = aws_sns_topic.budget_alerts.arn }
output "budget_name"             { value = aws_budgets_budget.demo.name }
