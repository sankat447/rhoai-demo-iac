# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT: demo — Key Outputs
# Run: terraform output -json > demo-outputs.json  (after apply)
# ─────────────────────────────────────────────────────────────────────────────

output "vpc_id"              { value = module.vpc.vpc_id;              description = "VPC ID" }
output "private_subnet_ids"  { value = module.vpc.private_subnet_ids;  description = "Private subnet IDs" }
output "nat_gateway_ip"      { value = module.vpc.nat_gateway_ip;      description = "Whitelist in external systems if needed" }

output "rosa_cluster_id"     { value = module.rosa.cluster_id;         description = "ROSA cluster ID" }
output "rosa_api_url"        { value = module.rosa.api_url;            description = "oc login --server=THIS_URL" }
output "rosa_console_url"    { value = module.rosa.console_url;        description = "OpenShift web console" }
output "oidc_endpoint_url"   { value = module.rosa.oidc_endpoint_url;  description = "OIDC URL for IRSA — already wired to iam-irsa module" }

output "s3_bucket_name"      { value = module.s3.bucket_name;          description = "Main data lake bucket" }
output "ecr_repository_urls" { value = module.ecr.repository_urls;     description = "Map of ECR repo URLs for docker push" }

output "aurora_endpoint"     { value = module.aurora.cluster_endpoint; description = "DB endpoint — use SSM path for password" }
output "aurora_ssm_password" { value = module.aurora.ssm_password_path; description = "SSM path — run: aws ssm get-parameter --name THIS --with-decryption" }
output "aurora_ssm_endpoint" { value = module.aurora.ssm_endpoint_path }

output "efs_file_system_id"  { value = module.efs.file_system_id;      description = "Use in AWS EFS CSI StorageClass YAML on ROSA" }
output "efs_access_point_id" { value = module.efs.access_point_id }

output "bedrock_role_arn"    { value = module.iam_irsa.bedrock_role_arn; description = "Annotate LangChain service accounts with this ARN" }
output "s3_role_arn"         { value = module.iam_irsa.s3_role_arn;      description = "Annotate RHOAI service accounts with this ARN" }

output "budget_name"         { value = module.lambda.budget_name;       description = "AWS Budget name for cost monitoring" }

# ── Quick Start commands (printed after apply) ────────────────────────────────
output "next_steps" {
  description = "Commands to run after terraform apply completes"
  value = <<-STEPS
  ── NEXT STEPS ──────────────────────────────────────────────────────────────
  1. Login to ROSA:
     rosa login --token=$RHCS_TOKEN
     oc login --server=${module.rosa.api_url} --username=cluster-admin

  2. Install RHOAI operator:
     rosa install-addon --cluster=${var.rosa_cluster_name} managed-odh

  3. Install AWS EFS CSI driver:
     rosa install-addon --cluster=${var.rosa_cluster_name} aws-efs-csi-driver-operator

  4. Initialise pgvector (run from bastion/SSM session):
     psql "postgresql://${var.db_master_username}:PASSWORD@${module.aurora.cluster_endpoint}/${var.db_name}" -f ../../modules/aurora-serverless/init.sql

  5. Bootstrap ArgoCD (application layer — separate repo):
     helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace
     oc apply -f <your-gitops-repo>/argocd-apps/

  6. Get DB password from SSM:
     aws ssm get-parameter --name ${module.aurora.ssm_password_path} --with-decryption --query Parameter.Value --output text
  ─────────────────────────────────────────────────────────────────────────────
  STEPS
}
