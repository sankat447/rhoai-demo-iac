# Production environment — same provider versions as demo
# Copy from environments/demo/versions.tf and adjust default_tags
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws  = { source = "hashicorp/aws";           version = "~> 5.50" }
    rhcs = { source = "terraform-redhat/rhcs";   version = "~> 1.6"  }
    random  = { source = "hashicorp/random";     version = "~> 3.6"  }
    archive = { source = "hashicorp/archive";    version = "~> 2.4"  }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = "production"
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = var.owner_tag
    }
  }
}
provider "rhcs" {}
