# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT: demo — Provider version constraints
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # All resources get these tags automatically
  default_tags {
    tags = {
      Environment = "demo"
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = var.owner_tag
      CostCenter  = "rhoai-demo"
    }
  }
}

provider "rhcs" {
  # Token read from environment variable RHCS_TOKEN
  # Set: export RHCS_TOKEN=$(cat ~/rh-ocm-token.json)
  # Or: aws-vault exec rhoai-demo -- terraform apply (reads from SSM at runtime)
}
