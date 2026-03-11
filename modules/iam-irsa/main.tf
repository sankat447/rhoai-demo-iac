# ─────────────────────────────────────────────────────────────────────────────
# MODULE: iam-irsa
# Purpose : IAM Roles for Service Accounts (IRSA) using OIDC federation
#
# IRSA allows ROSA pods to assume AWS IAM roles WITHOUT static credentials.
# The pod's Kubernetes service account is bound to an IAM role via OIDC.
#
# Roles created:
#   1. rhoai-s3-access       — RHOAI notebooks + pipelines read/write S3
#   2. rhoai-bedrock-access  — LangChain agents call Amazon Bedrock
#   3. rhoai-ecr-access      — ROSA nodes pull images from ECR
#   4. rhoai-ssm-access      — Pods read secrets from SSM Parameter Store
# ─────────────────────────────────────────────────────────────────────────────

# ── OIDC Provider lookup (created by ROSA) ───────────────────────────────────
data "aws_iam_openid_connect_provider" "rosa" {
  url = var.oidc_endpoint_url
}

locals {
  oidc_url    = replace(var.oidc_endpoint_url, "https://", "")
  oidc_arn    = data.aws_iam_openid_connect_provider.rosa.arn
}

# ── Helper: OIDC trust policy factory ────────────────────────────────────────
# Reusable template — namespace:serviceaccount wildcard pattern
data "aws_iam_policy_document" "assume_role" {
  for_each = var.service_account_roles

  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringLike"
      variable = "${local.oidc_url}:sub"
      # Pattern: system:serviceaccount:<namespace>:<sa-name>
      values = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ── Role 1: S3 Access — RHOAI notebooks, KFP pipelines, model storage ────────
resource "aws_iam_role" "s3_access" {
  name               = "${var.cluster_name}-rhoai-s3-access"
  assume_role_policy = data.aws_iam_policy_document.assume_role["s3"].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "s3_access" {
  name = "s3-rw-policy"
  role = aws_iam_role.s3_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBuckets"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
        ]
      },
      {
        Sid    = "ReadWriteObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject",
          "s3:DeleteObject", "s3:CopyObject",
          "s3:GetObjectTagging", "s3:PutObjectTagging"
        ]
        Resource = ["arn:aws:s3:::${var.s3_bucket_name}/*"]
      }
    ]
  })
}

# ── Role 2: Bedrock Access — LangChain agents, Open WebUI ────────────────────
resource "aws_iam_role" "bedrock_access" {
  count = var.enable_bedrock_access ? 1 : 0

  name               = "${var.cluster_name}-rhoai-bedrock-access"
  assume_role_policy = data.aws_iam_policy_document.assume_role["bedrock"].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "bedrock_access" {
  count = var.enable_bedrock_access ? 1 : 0

  name = "bedrock-invoke-policy"
  role = aws_iam_role.bedrock_access[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeFoundationModels"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        # Restrict to specific models in production; wildcard is fine for demo
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      },
      {
        Sid    = "BedrockEmbeddings"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
      }
    ]
  })
}

# ── Role 3: ECR Pull — ROSA nodes + RHOAI custom images ──────────────────────
resource "aws_iam_role" "ecr_access" {
  name               = "${var.cluster_name}-rhoai-ecr-access"
  assume_role_policy = data.aws_iam_policy_document.assume_role["ecr"].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ecr_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── Role 4: SSM Parameter Store — secrets for pods ───────────────────────────
resource "aws_iam_role" "ssm_access" {
  name               = "${var.cluster_name}-rhoai-ssm-access"
  assume_role_policy = data.aws_iam_policy_document.assume_role["ssm"].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "ssm_access" {
  name = "ssm-read-policy"
  role = aws_iam_role.ssm_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        # Restrict to /rhoai-demo/* namespace only
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.ssm_path_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}
