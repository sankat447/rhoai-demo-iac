terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_PROD_TFSTATE_BUCKET"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_PROD_DYNAMO_TABLE"
    encrypt        = true
  }
}
