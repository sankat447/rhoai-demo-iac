output "s3_role_arn"      { value = aws_iam_role.s3_access.arn;          description = "ARN of S3 access role — annotate RHOAI service accounts with this" }
output "bedrock_role_arn" { value = try(aws_iam_role.bedrock_access[0].arn, ""); description = "ARN of Bedrock access role — annotate LangChain service accounts" }
output "ecr_role_arn"     { value = aws_iam_role.ecr_access.arn;         description = "ARN of ECR pull role" }
output "ssm_role_arn"     { value = aws_iam_role.ssm_access.arn;         description = "ARN of SSM read role" }
