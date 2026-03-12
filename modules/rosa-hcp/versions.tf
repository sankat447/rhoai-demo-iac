terraform {
  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.6"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}
