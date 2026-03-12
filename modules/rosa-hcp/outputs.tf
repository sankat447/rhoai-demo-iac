output "cluster_id" {
  value       = rhcs_cluster_rosa_hcp.this.id
  description = "ROSA cluster ID"
}

output "cluster_name" {
  value       = rhcs_cluster_rosa_hcp.this.name
  description = "ROSA cluster name"
}

output "api_url" {
  value       = rhcs_cluster_rosa_hcp.this.api_url
  description = "OCP API URL — use for: oc login --server=THIS"
}

output "console_url" {
  value       = rhcs_cluster_rosa_hcp.this.console_url
  description = "OpenShift web console URL"
}

output "oidc_endpoint_url" {
  value       = rhcs_cluster_rosa_hcp.this.sts.oidc_endpoint_url
  description = "OIDC endpoint — pass to iam-irsa module"
}

output "cluster_state" {
  value       = rhcs_cluster_rosa_hcp.this.state
  description = "Current cluster state"
}
