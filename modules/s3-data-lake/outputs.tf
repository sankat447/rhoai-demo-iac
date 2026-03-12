output "bucket_name" {
  value = aws_s3_bucket.main.bucket
  description = "Main data lake bucket name — use in IRSA policy + RHOAI pipelines"
}
output "bucket_arn" {
  value = aws_s3_bucket.main.arn
  description = "Bucket ARN — use in IAM policies"
}
output "tfstate_bucket_name" {
  value = try(aws_s3_bucket.tfstate[0].bucket, "")
  description = "Terraform state bucket name — set in backend.tf"
}
output "tflock_table_name" {
  value = try(aws_dynamodb_table.tflock[0].name, "")
  description = "DynamoDB lock table name — set in backend.tf"
}
