# ─────────────────────────────────────────────────────────────────────────────
# MODULE: ecr-repos
# Purpose : Amazon ECR repositories for RHOAI custom container images
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability  # "MUTABLE" for demo, "IMMUTABLE" for prod

  image_scanning_configuration {
    scan_on_push = var.scan_on_push   # Scans for CVEs automatically on push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Name = each.value })
}

# ── Lifecycle policy — auto-delete untagged images to save storage cost ────────
resource "aws_ecr_lifecycle_policy" "repos" {
  for_each   = aws_ecr_repository.repos
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_images_to_keep} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest", "main"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_images_to_keep
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ── ECR Pull-through cache for Red Hat Quay (optional) ───────────────────────
# Caches images from quay.io to avoid rate limits in CI
resource "aws_ecr_pull_through_cache_rule" "quay" {
  count                 = var.enable_quay_pullthrough ? 1 : 0
  ecr_repository_prefix = "quay"
  upstream_registry_url = "quay.io"
}
