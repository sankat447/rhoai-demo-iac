# ─────────────────────────────────────────────────────────────────────────────
# MODULE: lambda-triggers
# Purpose : Platform-level Lambda functions for demo lifecycle automation
#
# Functions:
#   1. demo-start-scheduler  — EventBridge cron to scale ROSA workers up each morning
#   2. demo-stop-scheduler   — EventBridge cron to scale ROSA workers down each evening
#   3. budget-alert-handler  — SNS handler for AWS Budget alerts
#
# NOTE: LangChain/agent Lambda functions live in the APPLICATION layer (GitOps repo)
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ── IAM Role for Lambda ───────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_exec" {
  name = "${var.name}-lambda-platform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_rosa_control" {
  name = "rosa-scale-control"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow Lambda to control ROSA machine pools via ROSA API
        # ROSA CLI makes API calls to Red Hat OCM — credentials stored in SSM
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:*:parameter/${var.ssm_path_prefix}/*"
      },
      {
        # Allow SNS publish for budget alerts
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.budget_alerts.arn
      }
    ]
  })
}

# ── Lambda function source (inline Python) ────────────────────────────────────
data "archive_file" "scheduler_zip" {
  type        = "zip"
  output_path = "/tmp/demo-scheduler.zip"

  source {
    content  = <<-PYTHON
import boto3, os, json, subprocess

def handler(event, context):
    action = event.get("action", "unknown")
    cluster = os.environ["ROSA_CLUSTER_NAME"]
    replicas = os.environ.get("REPLICAS", "2")

    ssm = boto3.client("ssm")
    token = ssm.get_parameter(
        Name=f"/{os.environ['SSM_PREFIX']}/rh-ocm-token",
        WithDecryption=True
    )["Parameter"]["Value"]

    # ROSA CLI call — edit machine pool replicas
    cmd = [
        "rosa", "edit", "machinepool", "workers",
        f"--cluster={cluster}",
        f"--replicas={replicas}",
        f"--token={token}"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)

    print(f"Action={action} cluster={cluster} replicas={replicas}")
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr)
        raise Exception(f"rosa edit machinepool failed: {result.stderr}")

    return {"statusCode": 200, "action": action, "replicas": int(replicas)}
PYTHON
    filename = "handler.py"
  }
}

resource "aws_lambda_function" "demo_scheduler" {
  function_name    = "${var.name}-demo-scheduler"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.scheduler_zip.output_path
  source_code_hash = data.archive_file.scheduler_zip.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      ROSA_CLUSTER_NAME = var.rosa_cluster_name
      SSM_PREFIX        = var.ssm_path_prefix
    }
  }

  tags = var.tags
}

# ── EventBridge rules — morning start / evening stop ────────────────────────
resource "aws_cloudwatch_event_rule" "start" {
  name                = "${var.name}-demo-start"
  description         = "Scale ROSA workers up for demo (weekdays 8am)"
  schedule_expression = var.start_schedule_cron   # "cron(0 8 ? * MON-FRI *)"
  tags                = var.tags
}

resource "aws_cloudwatch_event_rule" "stop" {
  name                = "${var.name}-demo-stop"
  description         = "Scale ROSA workers down after demo (weekdays 8pm)"
  schedule_expression = var.stop_schedule_cron    # "cron(0 20 ? * MON-FRI *)"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "start" {
  rule      = aws_cloudwatch_event_rule.start.name
  target_id = "demo-start"
  arn       = aws_lambda_function.demo_scheduler.arn
  input     = jsonencode({ action = "start", REPLICAS = "2" })
}

resource "aws_cloudwatch_event_target" "stop" {
  rule      = aws_cloudwatch_event_rule.stop.name
  target_id = "demo-stop"
  arn       = aws_lambda_function.demo_scheduler.arn
  input     = jsonencode({ action = "stop", REPLICAS = "0" })
}

resource "aws_lambda_permission" "start" {
  statement_id  = "AllowEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.demo_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start.arn
}

resource "aws_lambda_permission" "stop" {
  statement_id  = "AllowEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.demo_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop.arn
}

# ── Budget Alert SNS Topic ────────────────────────────────────────────────────
resource "aws_sns_topic" "budget_alerts" {
  name = "${var.name}-budget-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "budget_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── AWS Budget — prevent surprise bills ──────────────────────────────────────
resource "aws_budgets_budget" "demo" {
  name         = "${var.name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}
