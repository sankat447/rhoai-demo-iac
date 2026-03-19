# ─────────────────────────────────────────────────────────────────────────────
# MODULE: s3-data-lake
# Purpose : S3 buckets for model storage, datasets, pipeline artifacts, Terraform state
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${var.bucket_prefix}-${local.account_id}"
}

# ── Main Data Bucket ──────────────────────────────────────────────────────────
resource "aws_s3_bucket" "main" {
  bucket        = local.bucket_name
  force_destroy = true   # Allow terraform destroy to delete bucket even with versioned objects
  tags          = merge(var.tags, { Name = local.bucket_name, Purpose = "rhoai-data-lake" })
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Lifecycle rules — auto-expire old pipeline artifacts to save cost ─────────
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "expire-pipeline-logs"
    status = "Enabled"
    filter { prefix = "pipelines/logs/" }
    expiration { days = var.pipeline_log_retention_days }
  }

  rule {
    id     = "archive-old-models"
    status = "Enabled"
    filter { prefix = "models/archived/" }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# ── Folder structure (empty objects as placeholders) ─────────────────────────
resource "aws_s3_object" "folders" {
  for_each = toset(var.folder_prefixes)

  bucket  = aws_s3_bucket.main.id
  key     = each.value
  content = ""
  tags    = var.tags
}

# ── Terraform State Bucket (separate, versioned, locked) ─────────────────────
resource "aws_s3_bucket" "tfstate" {
  count  = var.create_tfstate_bucket ? 1 : 0
  bucket = "${var.bucket_prefix}-tfstate-${local.account_id}"
  tags   = merge(var.tags, { Name = "terraform-state", Purpose = "tfstate" })
}

resource "aws_s3_bucket_versioning" "tfstate" {
  count  = var.create_tfstate_bucket ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  count  = var.create_tfstate_bucket ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  count                   = var.create_tfstate_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.tfstate[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB table for Terraform state lock ───────────────────────────────────
resource "aws_dynamodb_table" "tflock" {
  count        = var.create_tfstate_bucket ? 1 : 0
  name         = "${var.bucket_prefix}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, { Name = "terraform-state-lock" })
}
