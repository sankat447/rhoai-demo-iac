# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT: demo — Remote State Backend
#
# BOOTSTRAP FIRST:
#   Run scripts/bootstrap-state.sh to create the S3 bucket and DynamoDB table
#   before running terraform init with this backend config.
#
# Fill in your values below (do NOT use variables here — Terraform limitation).
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  backend "s3" {
    # ── FILL IN YOUR VALUES ──────────────────────────────────────────────────
    bucket         = "REPLACE_WITH_TFSTATE_BUCKET_NAME"    # e.g. rhoai-demo-tfstate-123456789012
    key            = "demo/terraform.tfstate"
    region         = "us-east-1"                           # Must match var.aws_region
    dynamodb_table = "REPLACE_WITH_DYNAMODB_TABLE_NAME"    # e.g. rhoai-demo-tflock
    encrypt        = true
    # ─────────────────────────────────────────────────────────────────────────
  }
}
