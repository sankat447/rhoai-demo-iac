output "repository_urls" {
  value       = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
  description = "Map of repo name to URL — use in docker push / Helm values"
}
output "registry_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "ECR registry ID (same as AWS account ID)"
}
